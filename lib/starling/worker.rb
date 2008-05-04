require 'rubygems'
require 'logger'
require 'thread'
require 'starling/thread_pool'

module StarlingWorker
  attr_reader :logger
  
  class Base
    VERSION = "0.0.1"
    
    DEFAULT_TIMEOUT     = 10
    DEFAULT_QUEUE_NAME  = name.gsub(/::/, '_').gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr("-", "_").downcase #tablize it

    # you just need to reimplement this
    def process
      raise "you need to implement process"
    end
    
    def initialize(starling, opts = {})
      @opts = {
        :timeout => DEFAULT_TIMEOUT,
        :queue_name => DEFAULT_QUEUE_NAME
      }.merge(opts)
      
      @@logger = case @opts[:logger]
                 when IO, String; Logger.new(@opts[:logger])
                 when Logger; @opts[:logger]
                 else; Logger.new(STDERR)
                 end
      
      @@logger = SyslogLogger.new(@opts[:syslog_channel]) if @opts[:syslog_channel]

      @@logger.level = @opts[:log_level] || Logger::ERROR

      @@logger.info "StarlingWorker::Base STARTUP"
      
      if starling
        @starling = starling
      else
        raise "you need to pass starling"
      end
      
      @threadpool = ThreadPool.new(10)
      
      @messages = Queue.new #local queue
    end
    
    def threadpool
      @threadpool
    end
    
    def process_as_thread
      @threadpool.add_work do
        # doing nothing
      end
    end
    
    def queue_name
      @opts[:queue_name]
    end
    
    def add_message_to_local_queue(message)
      @messages.enq message
      true
    end
    
    def get_message_from_local_queue
      @messages.deq
    end
    
    def local_queue
      @messages
    end
    
    def add_message_to_remote_queue(message)
      @starling.set("default", message)
      true
    end
    
    def get_message_from_remote_queue
      @starling.get("default")
    end
    
    def connected_to_starling?
      # TODO check if you are still connected, else reset
      return true if @starling
    end
    
    def close_connection_to_server
      @memcache.close
    end
    
    def self.logger
      @@logger
    end
  end
end