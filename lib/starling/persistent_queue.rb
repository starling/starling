module StarlingServer

  ##
  # PersistentQueue is a subclass of Ruby's thread-safe Queue class. It adds a
  # transactional log to the in-memory Queue, which enables quickly rebuilding
  # the Queue in the event of a sever outage.

  class PersistentQueue < Queue

    ##
    # When a log reaches the SOFT_LOG_MAX_SIZE, the Queue will wait until
    # it is empty, and will then rotate the log file.

    SOFT_LOG_MAX_SIZE = 16 * (1024**2) # 16 MB

    TRX_CMD_PUSH = "\000".freeze
    TRX_CMD_POP = "\001".freeze

    TRX_PUSH = "\000%s%s".freeze
    TRX_POP = "\001".freeze

    attr_reader :initial_bytes
    attr_reader :total_items
    attr_reader :logsize
    attr_reader :current_age

    ##
    # Create a new PersistentQueue at +persistence_path+/+queue_name+.
    # If a queue log exists at that path, the Queue will be loaded from
    # disk before being available for use.

    def initialize(persistence_path, queue_name, debug = false)
      @persistence_path = persistence_path
      @queue_name = queue_name
      @total_items = 0
      super()
      @initial_bytes = replay_transaction_log(debug)
      @current_age = 0
    end

    ##
    # Pushes +value+ to the queue. By default, +push+ will write to the
    # transactional log. Set +log_trx=false+ to override this behaviour.

    def push(value, log_trx = true)
      if log_trx
        raise NoTransactionLog unless @trx
        size = [value.size].pack("I")
        transaction sprintf(TRX_PUSH, size, value)
      end

      @total_items += 1
      super([now_usec, value])
    end

    ##
    # Retrieves data from the queue.

    def pop(log_trx = true)
      raise NoTransactionLog if log_trx && !@trx

      begin
        rv = super(!log_trx)
      rescue ThreadError
        puts "WARNING: The queue was empty when trying to pop(). Technically this shouldn't ever happen. Probably a bug in the transactional underpinnings. Or maybe shutdown didn't happen cleanly at some point. Ignoring."
        rv = [now_usec, '']
      end
      transaction "\001" if log_trx
      @current_age = (now_usec - rv[0]) / 1000
      rv[1]
    end

    ##
    # Safely closes the transactional queue.

    def close
      # Ok, yeah, this is lame, and is *technically* a race condition. HOWEVER,
      # the QueueCollection *should* have stopped processing requests, and I don't
      # want to add yet another Mutex around all the push and pop methods. So we
      # do the next simplest thing, and minimize the time we'll stick around before
      # @trx is nil.
      @not_trx = @trx
      @trx = nil
      @not_trx.close
    end
    
    def purge
      close
      File.delete(log_path)
    end

    private

    def log_path #:nodoc:
      File.join(@persistence_path, @queue_name)
    end

    def reopen_log #:nodoc:
      @trx = File.new(log_path, File::CREAT|File::RDWR)
      @logsize = File.size(log_path)
    end

    def rotate_log #:nodoc:
      @trx.close
      backup_logfile = "#{log_path}.#{Time.now.to_i}"
      File.rename(log_path, backup_logfile)
      reopen_log
      File.unlink(backup_logfile)
    end

    def replay_transaction_log(debug) #:nodoc:
      reopen_log
      bytes_read = 0

      print "Reading back transaction log for #{@queue_name} " if debug

      while !@trx.eof?
        cmd = @trx.read(1)
        case cmd
        when TRX_CMD_PUSH
          print ">" if debug
          raw_size = @trx.read(4)
          next unless raw_size
          size = raw_size.unpack("I").first
          data = @trx.read(size)
          next unless data
          push(data, false)
          bytes_read += data.size
        when TRX_CMD_POP
          print "<" if debug
          bytes_read -= pop(false).size
        else
          puts "Error reading transaction log: " +
               "I don't understand '#{cmd}' (skipping)." if debug
        end
      end

      print " done.\n" if debug

      return bytes_read
    end

    def transaction(data) #:nodoc:
      raise "no transaction log handle. that totally sucks." unless @trx

      @trx.write_nonblock data
      @logsize += data.size
      rotate_log if @logsize > SOFT_LOG_MAX_SIZE && self.length == 0
    end
    
    def now_usec
      now = Time.now
      now.to_i * 1000000 + now.usec
    end
  end
end
