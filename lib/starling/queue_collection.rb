require 'thread'
require 'starling/persistent_queue'

module StarlingServer
  class InaccessibleQueuePath < Exception #:nodoc:
  end

  ##
  # QueueCollection is a proxy to a collection of PersistentQueue instances.

  class QueueCollection

    ##
    # Create a new QueueCollection at +path+

    def initialize(path)
      unless File.directory?(path) && File.writable?(path)
        raise InaccessibleQueuePath.new("'#{path}' must exist and be read-writable by #{Etc.getpwuid(Process.uid).name}.")
      end

      @shutdown_mutex = Mutex.new

      @path = path
      @logger = StarlingServer::Base.logger

      @queues = {}
      @queue_init_mutexes = {}

      @stats = Hash.new(0)
    end

    ##
    # Puts +data+ onto the queue named +key+

    def put(key, data)
      queue = queues(key)
      return nil unless queue

      @stats[:current_bytes] += data.size
      @stats[:total_items] += 1

      queue.push(data)

      return true
    end

    ##
    # Retrieves data from the queue named +key+

    def take(key)
      queue = queues(key)
      if queue.nil? || queue.length == 0
        @stats[:get_misses] += 1
        return nil
      else
        @stats[:get_hits] += 1
      end
      result = queue.pop
      @stats[:current_bytes] -= result.size
      result
    end
    
    def delete(key)
      queue = @queues.delete(key)
      return if queue.nil?
      queue.purge
    end

    ##
    # Returns all active queues.

    def queues(key=nil)
      return nil if @shutdown_mutex.locked?

      return @queues if key.nil?

      # First try to return the queue named 'key' if it's available.
      return @queues[key] if @queues[key]

      # If the queue wasn't available, create or get the mutex that will
      # wrap creation of the Queue.
      @queue_init_mutexes[key] ||= Mutex.new

      # Otherwise, check to see if another process is already loading
      # the queue named 'key'.
      if @queue_init_mutexes[key].locked?
        # return an empty/false result if we're waiting for the queue
        # to be loaded and we're not the first process to request the queue
        return nil
      else
        begin
          @queue_init_mutexes[key].lock
          # we've locked the mutex, but only go ahead if the queue hasn't
          # been loaded. There's a race condition otherwise, and we could
          # end up loading the queue multiple times.
          if @queues[key].nil?
            @queues[key] = PersistentQueue.new(@path, key)
            @stats[:current_bytes] += @queues[key].initial_bytes
          end
        rescue Object => exc
          puts "ZOMG There was an exception reading back the queue. That totally sucks."
          puts "The exception was: #{exc}. Backtrace: #{exc.backtrace.join("\n")}"
        ensure
          @queue_init_mutexes[key].unlock
        end
      end

      return @queues[key]
    end

    ##
    # Returns statistic +stat_name+ for the QueueCollection.
    #
    # Valid statistics are:
    #
    #   [:get_misses]    Total number of get requests with empty responses
    #   [:get_hits]      Total number of get requests that returned data
    #   [:current_bytes] Current size in bytes of items in the queues
    #   [:current_size]  Current number of items across all queues
    #   [:total_items]   Total number of items stored in queues.

    def stats(stat_name)
      case stat_name
      when nil; @stats
      when :current_size; current_size
      else; @stats[stat_name]
      end
    end

    ##
    # Safely close all queues.

    def close
      @shutdown_mutex.lock
      @queues.each_pair do |name,queue|
        queue.close
        @queues.delete(name)
      end
    end

    private

    def current_size #:nodoc:
      @queues.inject(0) { |m, (k,v)| m + v.length }
    end
  end
end
