module StarlingServer

  ##
  # This is an internal class that's used by Starling::Server to handle the
  # MemCache protocol and act as an interface between the Server and the
  # QueueCollection.

  class Handler < EventMachine::Connection

    DATA_PACK_FMT = "Ia*".freeze

    # ERROR responses
    ERR_UNKNOWN_COMMAND = "CLIENT_ERROR bad command line format\r\n".freeze

    # GET Responses
    GET_COMMAND = /\Aget (.{1,250})\s*\r\n/m
    GET_RESPONSE       = "VALUE %s %s %s\r\n%s\r\nEND\r\n".freeze
    GET_RESPONSE_EMPTY = "END\r\n".freeze

    # SET Responses
    SET_COMMAND = /\Aset (.{1,250}) ([0-9]+) ([0-9]+) ([0-9]+)\r\n/m
    SET_RESPONSE_SUCCESS  = "STORED\r\n".freeze
    SET_RESPONSE_FAILURE  = "NOT STORED\r\n".freeze
    SET_CLIENT_DATA_ERROR = "CLIENT_ERROR bad data chunk\r\nERROR\r\n".freeze
    
    # DELETE Responses
    DELETE_COMMAND = /\Adelete (.{1,250}) ([0-9]+)\r\n/m
    DELETE_RESPONSE = "END\r\n".freeze

    # STAT Response
    STATS_COMMAND = /\Astats\r\n/m
    STATS_RESPONSE = "STAT pid %d\r
STAT uptime %d\r
STAT time %d\r
STAT version %s\r
STAT rusage_user %0.6f\r
STAT rusage_system %0.6f\r
STAT curr_items %d\r
STAT total_items %d\r
STAT bytes %d\r
STAT curr_connections %d\r
STAT total_connections %d\r
STAT cmd_get %d\r
STAT cmd_set %d\r
STAT get_hits %d\r
STAT get_misses %d\r
STAT bytes_read %d\r
STAT bytes_written %d\r
STAT limit_maxbytes %d\r
%sEND\r\n".freeze
    QUEUE_STATS_RESPONSE = "STAT queue_%s_items %d\r
STAT queue_%s_total_items %d\r
STAT queue_%s_logsize %d\r
STAT queue_%s_expired_items %d\r
STAT queue_%s_age %d\r\n".freeze

    SHUTDOWN_COMMAND = /\Ashutdown\r\n/m


    @@next_session_id = 1

    ##
    # Creates a new handler for the MemCache protocol that communicates with a
    # given client.

    def initialize(options = {})
      @opts = options
    end

    ##
    # Process incoming commands from the attached client.

    def post_init
      @stash = []
      @data = ""
      @data_buf = ""
      @server = @opts[:server]
      @logger = StarlingServer::Base.logger
      @expiry_stats = Hash.new(0)
      @expected_length = nil
      @server.stats[:total_connections] += 1
      set_comm_inactivity_timeout @opts[:timeout]
      @queue_collection = @opts[:queue]

      @session_id = @@next_session_id
      @@next_session_id += 1

      peer = Socket.unpack_sockaddr_in(get_peername)
      #@logger.debug "(#{@session_id}) New session from #{peer[1]}:#{peer[0]}"
    end

    def receive_data(incoming)
      @server.stats[:bytes_read] += incoming.size
      @data << incoming

      while data = @data.slice!(/.*?\r\n/m)
        response = process(data)
      end

      send_data response if response
    end

    def process(data)
      data = @data_buf + data if @data_buf.size > 0
      # our only non-normal state is consuming an object's data
      # when @expected_length is present
      if @expected_length && data.size == @expected_length
        response = set_data(data)
        @data_buf = ""
        return response
      elsif @expected_length
        @data_buf = data
        return
      end
      case data
      when SET_COMMAND
        @server.stats[:set_requests] += 1
        set($1, $2, $3, $4.to_i)
      when GET_COMMAND
        @server.stats[:get_requests] += 1
        get($1)
      when STATS_COMMAND
        stats
      when SHUTDOWN_COMMAND
        # no point in responding, they'll never get it.
        Runner::shutdown
      when DELETE_COMMAND
        delete $1
      else
        logger.warn "Unknown command: #{data}."
        respond ERR_UNKNOWN_COMMAND
      end
    rescue => e
      logger.error "Error handling request: #{e}."
      logger.debug e.backtrace.join("\n")
      respond GET_RESPONSE_EMPTY
    end

    def unbind
      #@logger.debug "(#{@session_id}) connection ends"
    end

  private
  
    def delete(queue)
      @queue_collection.delete(queue)
      respond DELETE_RESPONSE
    end
  
    def respond(str, *args)
      response = sprintf(str, *args)
      @server.stats[:bytes_written] += response.length
      response
    end

    def set(key, flags, expiry, len)
      @expected_length = len + 2
      @stash = [ key, flags, expiry ]
      nil
    end

    def set_data(incoming)
      key, flags, expiry = @stash
      data = incoming.slice(0...@expected_length-2)
      @stash = []
      @expected_length = nil

      internal_data = [expiry.to_i, data].pack(DATA_PACK_FMT)
      if @queue_collection.put(key, internal_data)
        respond SET_RESPONSE_SUCCESS
      else
        respond SET_RESPONSE_FAILURE
      end
    end

    def get(key)
      now = Time.now.to_i

      while response = @queue_collection.take(key)
        expiry, data = response.unpack(DATA_PACK_FMT)

        break if expiry == 0 || expiry >= now

        @expiry_stats[key] += 1
        expiry, data = nil
      end

      if data
        respond GET_RESPONSE, key, 0, data.size, data
      else
        respond GET_RESPONSE_EMPTY
      end
    end

    def stats
      respond STATS_RESPONSE,
        Process.pid, # pid
        Time.now - @server.stats(:start_time), # uptime
        Time.now.to_i, # time
        StarlingServer::VERSION, # version
        Process.times.utime, # rusage_user
        Process.times.stime, # rusage_system
        @queue_collection.stats(:current_size), # curr_items
        @queue_collection.stats(:total_items), # total_items
        @queue_collection.stats(:current_bytes), # bytes
        @server.stats(:connections), # curr_connections
        @server.stats(:total_connections), # total_connections
        @server.stats(:get_requests), # get count
        @server.stats(:set_requests), # set count
        @queue_collection.stats(:get_hits),
        @queue_collection.stats(:get_misses),
        @server.stats(:bytes_read), # total bytes read
        @server.stats(:bytes_written), # total bytes written
        0, # limit_maxbytes
        queue_stats
    end

    def queue_stats
      @queue_collection.queues.inject("") do |m,(k,v)|
        m + sprintf(QUEUE_STATS_RESPONSE,
                      k, v.length,
                      k, v.total_items,
                      k, v.logsize,
                      k, @expiry_stats[k],
                      k, v.current_age)
      end
    end

    def logger
      @logger
    end
  end
end
