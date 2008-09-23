$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'rubygems'
require 'fileutils'
require 'memcache'
require 'digest/md5'
require 'starling'

require 'starling/server'

class StarlingServer::PersistentQueue
  remove_const :SOFT_LOG_MAX_SIZE
  SOFT_LOG_MAX_SIZE = 16 * 1024 # 16 KB
end

def safely_fork(&block)
  # anti-race juice:
  blocking = true
  Signal.trap("USR1") { blocking = false }
  
  pid = Process.fork(&block)
  
  while blocking
    sleep 0.1
  end

  pid
end

describe "StarlingServer" do
  before do
    @tmp_path = File.join(File.dirname(__FILE__), "tmp")
    
    begin
      Dir::mkdir(@tmp_path)
    rescue Errno::EEXIST
    end

    @server_pid = safely_fork do
      server = StarlingServer::Base.new(:host => '127.0.0.1',
                                        :port => 22133,
                                        :path => @tmp_path,
                                        :logger => Logger.new(STDERR),
                                        :log_level => Logger::FATAL)
      Signal.trap("INT") {
        server.stop
        exit
      }

      Process.kill("USR1", Process.ppid)
      server.run
    end

    @client = MemCache.new('127.0.0.1:22133')

  end
  
  it "should test if temp_path exists and is writeable" do
    File.exist?(@tmp_path).should be_true
    File.directory?(@tmp_path).should be_true
    File.writable?(@tmp_path).should be_true
  end

  it "should set and get" do
    v = rand((2**32)-1)
    @client.get('test_set_and_get_one_entry').should be_nil
    @client.set('test_set_and_get_one_entry', v)
    @client.get('test_set_and_get_one_entry').should eql(v)
  end
  
  it "should respond to delete" do
    @client.delete("my_queue").should eql("END\r\n")   
    starling_client = Starling.new('127.0.0.1:22133')
    starling_client.set('my_queue', 50)
    starling_client.available_queues.size.should eql(1)
    starling_client.delete("my_queue")
    starling_client.available_queues.size.should eql(0)
  end
  
  it "should expire entries" do
    v = rand((2**32)-1)
    @client.get('test_set_with_expiry').should be_nil
    now = Time.now.to_i
    @client.set('test_set_with_expiry', v + 2, now)
    @client.set('test_set_with_expiry', v)
    sleep(1.0)
    @client.get('test_set_with_expiry').should eql(v)
  end

  it "should have age stat" do
    now = Time.now.to_i
    @client.set('test_age', 'nibbler')
    sleep(1.0)
    @client.get('test_age').should eql('nibbler')

    stats = @client.stats['127.0.0.1:22133']
    stats.has_key?('queue_test_age_age').should be_true
    (stats['queue_test_age_age'] >= 1000).should be_true
  end
  
  it "should rotate log" do
    log_rotation_path = File.join(@tmp_path, 'test_log_rotation')

    Dir.glob("#{log_rotation_path}*").each do |file|
      File.unlink(file) rescue nil
    end
    @client.get('test_log_rotation').should be_nil

    v = 'x' * 8192

    @client.set('test_log_rotation', v)
    File.size(log_rotation_path).should eql(8207)
    @client.get('test_log_rotation')

    @client.get('test_log_rotation').should be_nil

    @client.set('test_log_rotation', v)
    @client.get('test_log_rotation').should eql(v)

    File.size(log_rotation_path).should eql(1)
    # rotated log should be erased after a successful roll.
    Dir.glob("#{log_rotation_path}*").size.should eql(1)
  end

  it "should output statistics per server" do
    stats = @client.stats
    assert_kind_of Hash, stats
    assert stats.has_key?('127.0.0.1:22133')
    
    server_stats = stats['127.0.0.1:22133']
    
    basic_stats = %w( bytes pid time limit_maxbytes cmd_get version
                      bytes_written cmd_set get_misses total_connections
                      curr_connections curr_items uptime get_hits total_items
                      rusage_system rusage_user bytes_read )

    basic_stats.each do |stat|
      server_stats.has_key?(stat).should be_true
    end
  end

  it "should return valid response with unkown command" do
    response = @client.add('blah', 1)
    response.should eql("CLIENT_ERROR bad command line format\r\n")
  end

  it "should disconnect and reconnect again" do
    v = rand(2**32-1)
    @client.set('test_that_disconnecting_and_reconnecting_works', v)
    @client.reset
    @client.get('test_that_disconnecting_and_reconnecting_works').should eql(v)
  end
  
  it "should use epoll on linux" do
    # this may take a few seconds.
    # the point is to make sure that we're using epoll on Linux, so we can
    # handle more than 1024 connections.
    
    unless IO::popen("uname").read.chomp == "Linux"
      pending "skipping epoll test: not on Linux"
    end

    fd_limit = IO::popen("bash -c 'ulimit -n'").read.chomp.to_i
    unless fd_limit > 1024
      pending "skipping epoll test: 'ulimit -n' = #{fd_limit}, need > 1024"
    end
    
    v = rand(2**32 - 1)
    @client.set('test_epoll', v)

    # we can't open 1024 connections to memcache from within this process,
    # because we will hit ruby's 1024 fd limit ourselves!
    pid1 = safely_fork do
      unused_sockets = []
      600.times do
        unused_sockets << TCPSocket.new("127.0.0.1", 22133)
      end
      Process.kill("USR1", Process.ppid)
      sleep 90
    end
    pid2 = safely_fork do
      unused_sockets = []
      600.times do
        unused_sockets << TCPSocket.new("127.0.0.1", 22133)
      end
      Process.kill("USR1", Process.ppid)
      sleep 90
    end

    begin
      client = MemCache.new('127.0.0.1:22133')
      client.get('test_epoll').should eql(v)
    ensure
      Process.kill("TERM", pid1)
      Process.kill("TERM", pid2)
    end
  end
  
  it "should raise error if queue collection is an invalid path" do
    invalid_path = nil
    while invalid_path.nil? || File.exist?(invalid_path)
      invalid_path = File.join('/', Digest::MD5.hexdigest(rand(2**32-1).to_s)[0,8])
    end

    lambda {
      StarlingServer::QueueCollection.new(invalid_path)
    }.should raise_error(StarlingServer::InaccessibleQueuePath)
  end
  
  after do
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    @client.reset
    FileUtils.rm(Dir.glob(File.join(@tmp_path, '*')))
  end
end
