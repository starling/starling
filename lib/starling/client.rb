require 'logger'
require 'eventmachine'
require 'analyzer_tools/syslog_logger'

here = File.dirname(__FILE__)

module StarlingClient

  VERSION = "0.0.1"
  
  class Base
    attr_reader :logger
    
    DEFAULT_WORKER_PATH = here + "/workers/"
    DEFAULT_TIMEOUT     = 60

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
    # Initialize a new Starling client, but do not start with working
    #
    # +opts+ is as for +start+

    def initialize(opts = {})
      @opts = {
        :path    => DEFAULT_WORKER_PATH,
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

      @@logger = case @opts[:logger]
                 when IO, String; Logger.new(@opts[:logger])
                 when Logger; @opts[:logger]
                 else; Logger.new(STDERR)
                 end
      @@logger = SyslogLogger.new(@opts[:syslog_channel]) if @opts[:syslog_channel]

      @@logger.level = @opts[:log_level] || Logger::ERROR

      @@logger.info "Starling Client STARTUP"
    end

    def self.logger
      @@logger
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
