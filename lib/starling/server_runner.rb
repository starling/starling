require File.join(File.dirname(__FILE__), 'server')
require 'optparse'
require 'yaml'

module StarlingServer
  class Runner

    attr_accessor :options
    private :options, :options=

    def self.run
      new
    end
    
    def self.shutdown
      @@instance.shutdown
    end

    def initialize
      @@instance = self
      parse_options

      @process = ProcessHelper.new(options[:logger], options[:pid_file], options[:user], options[:group])

      pid = @process.running?
      if pid
        STDERR.puts "There is already a Starling process running (pid #{pid}), exiting."
        exit(1)
      elsif pid.nil?
        STDERR.puts "Cleaning up stale pidfile at #{options[:pid_file]}."
      end

      start
    end

    def load_config_file(filename)
      YAML.load(File.open(filename))['starling'].each do |key, value|
        # alias some keys
        case key
        when "queue_path" then key = "path"
        when "log_file" then key = "logger"
        end

        if %w(logger path pid_file).include?(key)
          value = File.expand_path(value)
        end

        options[key.to_sym] = value

        if options[:log_level].instance_of?(String)
          options[:log_level] = Logger.const_get(options[:log_level])
        end
      end
    end

    def parse_options
      self.options = { :host => '127.0.0.1',
                       :port => 22122,
                       :path => File.join('', 'var', 'spool', 'starling'),
                       :log_level => Logger::INFO,
                       :daemonize => false,
                       :timeout => 0,
                       :pid_file => File.join('', 'var', 'run', 'starling.pid') }

      OptionParser.new do |opts|
        opts.summary_width = 25

        opts.banner = "Starling (#{StarlingServer::VERSION})\n\n",
                      "usage: starling [options...]\n",
                      "       starling --help\n",
                      "       starling --version\n"

        opts.separator ""
        opts.separator "Configuration:"

        opts.on("-f", "--config FILENAME",
                "Config file (yaml) to load") do |filename|
          load_config_file(filename)
        end

        opts.on("-q", "--queue_path PATH",
                :REQUIRED,
                "Path to store Starling queue logs", "(default: #{options[:path]})") do |queue_path|
          options[:path] = File.expand_path(queue_path)
        end

        opts.separator ""; opts.separator "Network:"

        opts.on("-hHOST", "--host HOST", "Interface on which to listen (default: #{options[:host]})") do |host|
          options[:host] = host
        end

        opts.on("-pHOST", "--port PORT", Integer, "TCP port on which to listen (default: #{options[:port]})") do |port|
          options[:port] = port
        end

        opts.separator ""; opts.separator "Process:"

        opts.on("-d", "Run as a daemon.") do
          options[:daemonize] = true
        end

        opts.on("-PFILE", "--pid FILENAME", "save PID in FILENAME when using -d option.", "(default: #{options[:pid_file]})") do |pid_file|
          options[:pid_file] = File.expand_path(pid_file)
        end

        opts.on("-u", "--user USER", "User to run as") do |user|
          options[:user] = user.to_i == 0 ? Etc.getpwnam(user).uid : user.to_i
        end

        opts.on("-gGROUP", "--group GROUP", "Group to run as") do |group|
          options[:group] = group.to_i == 0 ? Etc.getgrnam(group).gid : group.to_i
        end

        opts.separator ""; opts.separator "Logging:"

        opts.on("-L", "--log [FILE]", "Path to print debugging information.") do |log_path|
          options[:logger] = File.expand_path(log_path)
        end

        begin
          require 'syslog_logger'

          opts.on("-l", "--syslog CHANNEL", "Write logs to the syslog instead of a log file.") do |channel|
            options[:syslog_channel] = channel
          end
        rescue LoadError
        end

        opts.on("-v", "Increase logging verbosity (may be used multiple times).") do
          options[:log_level] -= 1
        end

        opts.on("-t", "--timeout [SECONDS]", Integer,
                "Time in seconds before disconnecting inactive clients (0 to disable).",
                "(default: #{options[:timeout]})") do |timeout|
          options[:timeout] = timeout
        end

        opts.separator ""; opts.separator "Miscellaneous:"

        opts.on_tail("-?", "--help", "Display this usage information.") do
          puts "#{opts}\n"
          exit
        end

        opts.on_tail("-V", "--version", "Print version number and exit.") do
          puts "Starling #{StarlingServer::VERSION}\n\n"
          exit
        end
      end.parse!
    end

    def start
      drop_privileges

      @process.daemonize if options[:daemonize]

      setup_signal_traps
      @process.write_pid_file

      STDOUT.puts "Starting at #{options[:host]}:#{options[:port]}."
      @server = StarlingServer::Base.new(options)
      @server.run

      @process.remove_pid_file
    end

    def drop_privileges
      Process.egid = options[:group] if options[:group]
      Process.euid = options[:user] if options[:user]
    end

    def shutdown
      begin
        STDOUT.puts "Shutting down."
        StarlingServer::Base.logger.info "Shutting down."
        @server.stop
      rescue Object => e
        STDERR.puts "There was an error shutting down: #{e}"
        exit(70)
      end
    end

    def setup_signal_traps
      Signal.trap("INT") { shutdown }
      Signal.trap("TERM") { shutdown }
    end
  end

  class ProcessHelper

    def initialize(log_file = nil, pid_file = nil, user = nil, group = nil)
      @log_file = log_file
      @pid_file = pid_file
      @user = user
      @group = group
    end

    def safefork
      begin
        if pid = fork
          return pid
        end
      rescue Errno::EWOULDBLOCK
        sleep 5
        retry
      end
    end

    def daemonize
      sess_id = detach_from_terminal
      exit if pid = safefork

      Dir.chdir("/")
      File.umask 0000

      close_io_handles
      redirect_io

      return sess_id
    end

    def detach_from_terminal
      srand
      safefork and exit

      unless sess_id = Process.setsid
        raise "Couldn't detach from controlling terminal."
      end

      trap 'SIGHUP', 'IGNORE'

      sess_id
    end

    def close_io_handles
      ObjectSpace.each_object(IO) do |io|
        unless [STDIN, STDOUT, STDERR].include?(io)
          begin
            io.close unless io.closed?
          rescue Exception
          end
        end
      end
    end

    def redirect_io
      begin; STDIN.reopen('/dev/null'); rescue Exception; end

      if @log_file
        begin
          STDOUT.reopen(@log_file, "a")
          STDOUT.sync = true
        rescue Exception
          begin; STDOUT.reopen('/dev/null'); rescue Exception; end
        end
      else
        begin; STDOUT.reopen('/dev/null'); rescue Exception; end
      end

      begin; STDERR.reopen(STDOUT); rescue Exception; end
      STDERR.sync = true
    end

    def rescue_exception
      begin
        yield
      rescue Exception
      end
    end

    def write_pid_file
      return unless @pid_file
      FileUtils.mkdir_p(File.dirname(@pid_file))
      File.open(@pid_file, "w") { |f| f.write(Process.pid) }
      File.chmod(0644, @pid_file)
    end

    def remove_pid_file
      return unless @pid_file
      File.unlink(@pid_file) if File.exists?(@pid_file)
    end

    def running?
      return false unless @pid_file

      pid = File.read(@pid_file).chomp.to_i rescue nil
      pid = nil if pid == 0
      return false unless pid

      begin
        Process.kill(0, pid)
        return pid
      rescue Errno::ESRCH
        return nil
      rescue Errno::EPERM
        return pid
      end
    end
  end
end
