require 'socket'
require 'logger'
require 'rubygems'
require 'eventmachine'

here = File.dirname(__FILE__)

require File.join(here, 'queue_collection')
require File.join(here, 'handler')

module StarlingServer

  VERSION = "0.9.8"
  
  class Base
    attr_reader :logger

    DEFAULT_HOST    = '127.0.0.1'
    DEFAULT_PORT    = 22122
    DEFAULT_PATH    = "/tmp/starling/"
    DEFAULT_TIMEOUT = 60

    ##
    # Initialize a new Starling server and immediately start processing
    # requests.
    #
    # +opts+ is an optional hash, whose valid options are:
    #
    #   [:host]     Host on which to listen (default is 127.0.0.1).
    #   [:port]     Port on which to listen (default is 22122).
    #   [:path]     Path to Starling queue logs. Default is /tmp/starling/
    #   [:timeout]  Time in seconds to wait before closing connections.
    #   [:logger]   A Logger object, an IO handle, or a path to the log.
    #   [:loglevel] Logger verbosity. Default is Logger::ERROR.
    #
    # Other options are ignored.

    def self.start(opts = {})
      server = self.new(opts)
      server.run
    end

    ##
    # Initialize a new Starling server, but do not accept connections or
    # process requests.
    #
    # +opts+ is as for +start+

    def initialize(opts = {})
      @opts = {
        :host    => DEFAULT_HOST,
        :port    => DEFAULT_PORT,
        :path    => DEFAULT_PATH,
        :timeout => DEFAULT_TIMEOUT,
        :server  => self
      }.merge(opts)

      @stats = Hash.new(0)

      FileUtils.mkdir_p(@opts[:path])

    end

    ##
    # Start listening and processing requests.

    def run
      @stats[:start_time] = Time.now

      if @opts[:syslog_channel]
        begin
          require 'syslog_logger'
          @@logger = SyslogLogger.new(@opts[:syslog_channel])
        rescue LoadError
          # SyslogLogger isn't available, so we're just going to use Logger
        end
      end

      @@logger ||= case @opts[:logger]
                   when IO, String; Logger.new(@opts[:logger])
                   when Logger; @opts[:logger]
                   else; Logger.new(STDERR)
                   end

      begin
        @opts[:queue] = QueueCollection.new(@opts[:path])
      rescue InaccessibleQueuePath => e
        puts "Error: #{e.message}"
        exit 1
      end
      @@logger.level = @opts[:log_level] || Logger::ERROR

      @@logger.info "Starling STARTUP on #{@opts[:host]}:#{@opts[:port]}"

      EventMachine.epoll
      EventMachine.set_descriptor_table_size(4096)
      EventMachine.run do
        EventMachine.start_server(@opts[:host], @opts[:port], Handler, @opts)
      end

      # code here will get executed on shutdown:
      @opts[:queue].close
    end

    def self.logger
      @@logger
    end


    ##
    # Stop accepting new connections and shutdown gracefully.

    def stop
      EventMachine.stop_event_loop
    end

    def stats(stat = nil) #:nodoc:
      case stat
      when nil; @stats
      when :connections; 1
      else; @stats[stat]
      end
    end
  end
end
