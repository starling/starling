require 'rubygems'
require 'logger'
require 'thread'
require 'timeout'
require 'starling/thread_pool'

module StarlingWorker
  attr_reader :logger
  
  class Base
    VERSION = "0.0.1"
    
    DEFAULT_TIMEOUT     = 10
    DEFAULT_REMOTE_INCOMING_QUEUE_NAME  = "#{name.gsub(/::/, '_').gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr("-", "_").downcase}_in" #tablize it
    DEFAULT_REMOTE_OUTGOING_QUEUE_NAME  = "#{name.gsub(/::/, '_').gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').gsub(/([a-z\d])([A-Z])/,'\1_\2').tr("-", "_").downcase}_out" #tablize it
    DEFAULT_CONTINUES_PROCESSING = true

    # you just need to reimplement this
    def process(message=nil, &block)
      if block
        @block = block
      else
        raise "you need to implement process"
      end
    end
    
    def run
      process_worker(&@block)
    end
    
    def initialize(opts = {})
      @opts = {
        :timeout => DEFAULT_TIMEOUT,
        :incoming_remote_queue_name => DEFAULT_REMOTE_INCOMING_QUEUE_NAME,
        :outgoing_remote_queue_name => DEFAULT_REMOTE_OUTGOING_QUEUE_NAME, 
        :continues_processing => DEFAULT_CONTINUES_PROCESSING
      }.merge(opts)
      
      @@logger = case @opts[:logger]
                 when IO, String; Logger.new(@opts[:logger])
                 when Logger; @opts[:logger]
                 else; Logger.new(STDERR)
                 end
      
      @@logger = SyslogLogger.new(@opts[:syslog_channel]) if @opts[:syslog_channel]

      @@logger.level = @opts[:log_level] || Logger::ERROR

      @@logger.info "StarlingWorker::Base STARTUP"
      
      unless @opts[:host] && @opts[:port]
        raise "you need to pass starling host en port"
      else
        @starling = Starling.new("localhost:22133", :multithread => true)
      end
      
      @threadpool = ThreadPool.new(10)
      
      @messages = Queue.new #local queue
    end
    
    def process_worker(&block)
      enq_thread = Thread.new do
        if @opts[:continues_processing]
          while @opts[:continues_processing]
            process_message_from_incoming_remote_queue(&block)
          end
        else
          process_message_from_incoming_remote_queue(&block)
        end
      end
      
      enq_thread.join unless @opts[:continues_processing]
      
      deq_thread = Thread.new do
        if @opts[:continues_processing]
          while @opts[:continues_processing]
            process_message_from_local_queue_to_outgoing_remote_queue
          end
        else
          process_message_from_local_queue_to_outgoing_remote_queue
        end
      end
      
      deq_thread.join unless @opts[:continues_processing]
    end
    
    def process_message_from_incoming_remote_queue(&block)
      begin
        starling = Starling.new("#{@opts[:host]}:#{@opts[:port]}", :multithread => true) unless starling

        message = from_remote_queue_to_process(starling)

        process_message(message, &block)
      rescue Exception => e
        puts "--- process_worker ---"
        puts e
        puts e.backtrace.join("\n")
        sleep 1
      end
    end
    
    def process_message_from_local_queue_to_outgoing_remote_queue
      begin
        starling = Starling.new("#{@opts[:host]}:#{@opts[:port]}", :multithread => true) unless starling

        from_local_queue_to_remote_queue(starling)
      rescue Exception => e
        puts "--- process_worker ---"
        puts e
        puts e.backtrace.join("\n")
        sleep 1
      end
    end
    
    def process_message(message, &block)
      @threadpool.add_work do
        timeout(@opts[:timeout]) do
          if block
            from_process_to_local_queue block.call(message)
          else
            from_process_to_local_queue process(message)
          end
        end
      end
    end
    
    def from_remote_queue_to_process(starling=@starling)
      message = get_message_from_incoming_remote_queue(starling)
      
      message
    end
    
    def from_process_to_local_queue(message)
      add_message_to_local_queue(message)
    end
    
    def from_local_queue_to_remote_queue(starling=@starling)
      message = get_message_from_local_queue
      
      starling.set(@opts[:outgoing_remote_queue_name], message)
    end
    
    def threadpool
      @threadpool
    end
    
    def incoming_remote_queue_name
      @opts[:incoming_remote_queue_name]
    end
    
    def outgoing_remote_queue_name
      @opts[:outgoing_remote_queue_name]
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
    
    def add_message_to_incoming_remote_queue(message, starling=@starling)
      starling.set(incoming_remote_queue_name, message)
      true
    end
    
    def get_message_from_incoming_remote_queue(starling=@starling)
      starling.get(incoming_remote_queue_name)
    end
    
    def add_message_to_outgoing_remote_queue(message, starling=@starling)
      starling.set(outgoing_remote_queue_name, message)
      true
    end
    
    def get_message_from_outgoing_remote_queue(starling=@starling)
      starling.get(outgoing_remote_queue_name)
    end
    
    def flush_remote_queue
      @starling.flush
    end
    
    def self.logger
      @@logger
    end
  end
end