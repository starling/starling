require 'rubygems'
require 'starling'
require 'starling/worker'
require 'logger'
require 'eventmachine'
require 'analyzer_tools/syslog_logger'

module StarlingClient

  VERSION = "0.9.7.5"
  
  class Base
    attr_reader :logger

    DEFAULT_HOST            = "localhost"
    DEFAULT_PORT            = "22122"
    DEFAULT_TEMPLATES_PATH  = File.join("tmp", "starling", "templates")
    DEFAULT_WORKERS_PATH    = File.join("tmp", "starling", "workers")
    DEFAULT_TIMEOUT         = 60

    ##
    # Initialize a new Starling client and immediately start processing
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
        :host           => DEFAULT_HOST,
        :port           => DEFAULT_PORT,
        :templates_path => DEFAULT_TEMPLATES_PATH,
        :workers_path   => DEFAULT_WORKERS_PATH,
        :timeout        => DEFAULT_TIMEOUT,
        :continues_processing => true
      }.merge(opts)

      @stats = Hash.new(0)

      FileUtils.mkdir_p(@opts[:templates_path])
      FileUtils.mkdir_p(@opts[:workers_path])
      
      @client = Starling.new("#{@opts[:host]}:#{@opts[:port]}", :multithread => true)
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
      
      load_templates
      
      @pids = []
      
      load_workers.each do |worker|
        @pids << fork {
          worker = StarlingWorker.const_get(worker).new(:host => @opts[:host],
                                                        :port => @opts[:port]).run
          @@logger.info "Starling Client STARTUP"
        }
      end
      
      if load_workers.length == 0
        @@logger.error "no workers found"
        @shutdown = true
      end
      
      loop {
        sleep 60
      } if @opts[:continues_processing]
    end
    
    def stop
      @pids.each do |pid|
        Process.kill(0, pid)
      end
      
      exit(0)
    end
    
    def load_templates
      templates = []
      Dir.glob("#{@opts[:templates_path]}/*.rb").each do |file|
        unless [".", ".."].include?(file)
          load(file) 
          templates << File.basename(file, ".rb").split('_').map{|w| w.capitalize}.join
        end
      end
      
      return templates
    end
    
    def load_workers
      workers = []
      Dir.glob("#{@opts[:workers_path]}/*.rb").each do |file|
        unless [".", ".."].include?(file)
          load(file) 
          workers << File.basename(file, ".rb").split('_').map{|w| w.capitalize}.join
        end
      end
      
      return workers
    end
    
    def starling
      return @client
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
