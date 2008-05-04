require 'rubygems'
require 'logger'
require 'thread'
require 'timeout'
require 'starling/thread_pool'

module StarlingWorker
  attr_reader :logger
  
  VERSION = "0.9.7.5"
  
  class Base    
    DEFAULT_TIMEOUT     = 10
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
        :incoming_remote_queue_name => nil,
        :outgoing_remote_queue_name => nil,
        :continues_processing => DEFAULT_CONTINUES_PROCESSING,
        :threads => 10,
        :log_level => Logger::INFO
      }.merge(opts)
      
      @@logger = case @opts[:logger]
                 when IO, String; Logger.new(@opts[:logger])
                 when Logger; @opts[:logger]
                 else; Logger.new(STDERR)
                 end
      
      @@logger = SyslogLogger.new(@opts[:syslog_channel]) if @opts[:syslog_channel]

      @@logger.level = @opts[:log_level] || Logger::ERROR

      @@logger.info "StarlingWorker#{self.class.to_s} STARTUP"
      
      unless @opts[:host] && @opts[:port]
        raise "you need to pass starling host en port"
      else
        @@logger.info "StarlingWorker#{self.class.to_s} connecting to starling"
        @starling = Starling.new("#{@opts[:host]}:#{@opts[:port]}", :multithread => true)
      end
      
      @@logger.info "StarlingWorker#{self.class.to_s} ThreadPool #{@opts[:threads]}"
      @threadpool = ThreadPool.new(@opts[:threads])
      
      @@logger.info "StarlingWorker#{self.class.to_s} Created local queue"
      @messages = Queue.new #local queue
    end
    
    def process_worker(&block)
      enq_thread = Thread.new do
        @@logger.info "StarlingWorker#{self.class.to_s} starting process_message_from_remote_queue"
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
        @@logger.info "StarlingWorker#{self.class.to_s} starting process_message_from_local_queue_to_outgoing_remote_queue"
        if @opts[:continues_processing]
          while @opts[:continues_processing]
            process_message_from_local_queue_to_outgoing_remote_queue
          end
        else
          process_message_from_local_queue_to_outgoing_remote_queue
        end
      end if @opts[:outgoing_remote_queue_name]
      
      deq_thread.join unless @opts[:continues_processing] || @opts[:outgoing_remote_queue_name] == nil
      
      if @opts[:continues_processing]
        enq_thread.join
        deq_thread.join unless @opts[:outgoing_remote_queue_name] == nil
      end
    end
    
    def process_message_from_incoming_remote_queue(&block)
      begin
        if @opts[:incoming_remote_queue_name]
          starling = Starling.new("#{@opts[:host]}:#{@opts[:port]}", :multithread => true) unless starling
          message = from_remote_queue_to_process(starling)
          while message == nil
            sleep 0.25
            message = from_remote_queue_to_process(starling)
          end
          @@logger.info "StarlingWorker#{self.class.to_s} processing message (#{message})"
          process_as_thread(message, &block)
        else
          @@logger.info "StarlingWorker#{self.class.to_s} processing without message (#{message})"
          process_as_thread(&block) # just process without message
        end
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
    
    def process_as_thread(message=nil, &block)
      @threadpool.add_work do
        timeout(@opts[:timeout]) do
          if block
            if message
              @@logger.info "StarlingWorker#{self.class.to_s} processing block message (#{message})"
              from_process_to_local_queue block.call(message)
            else
              @@logger.info "StarlingWorker#{self.class.to_s} processing block without message (#{message})"
              from_process_to_local_queue block.call
            end
          else
            if message
              @@logger.info "StarlingWorker#{self.class.to_s} processing method message (#{message})"
              from_process_to_local_queue process(message)
            else
              @@logger.info "StarlingWorker#{self.class.to_s} processing method without message (#{message})"
              from_process_to_local_queue process
            end
          end
        end
      end
    end
    
    def from_remote_queue_to_process(starling=@starling)
      if @opts[:incoming_remote_queue_name]
        message = get_message_from_incoming_remote_queue(starling)
        
        while message == nil
          sleep 0.25
          message = get_message_from_incoming_remote_queue(starling)
        end
        
        @@logger.info "StarlingWorker#{self.class.to_s} return remote message to process (#{message})"
      
        message
      end
    end
    
    def from_process_to_local_queue(message)
      @@logger.info "StarlingWorker#{self.class.to_s} add message to local queue (#{message})" if @opts[:outgoing_remote_queue_name]
      add_message_to_local_queue(message) if @opts[:outgoing_remote_queue_name]
    end
    
    def from_local_queue_to_remote_queue(starling=@starling)
      if @opts[:outgoing_remote_queue_name]
        message = get_message_from_local_queue
        
        @@logger.info "StarlingWorker::#{self.class.to_s} set message on remote queue (#{message})"
        
        starling.set(@opts[:outgoing_remote_queue_name], message)
      end
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