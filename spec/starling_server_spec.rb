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
    expect(File.exist?(@tmp_path)).to be_truthy
    expect(File.directory?(@tmp_path)).to be_truthy
    expect(File.writable?(@tmp_path)).to be_truthy
  end

  it "should set and get" do
    v = rand((2**32)-1)
    expect(@client.get('test_set_and_get_one_entry')).to be_nil
    @client.set('test_set_and_get_one_entry', v)
    expect(@client.get('test_set_and_get_one_entry')).to eql(v)
  end

  it "should respond to delete" do
    expect(@client.delete("my_queue")).to eql("NOT_FOUND\r\n")
    starling_client = Starling.new('127.0.0.1:22133')
    starling_client.set('my_queue', 50)
    expect(starling_client.available_queues.size).to eql(1)
    starling_client.delete("my_queue")
    expect(starling_client.available_queues.size).to eql(0)
  end

  it "should expire entries" do
    v = rand((2**32)-1)
    expect(@client.get('test_set_with_expiry')).to be_nil
    now = Time.now.to_i
    @client.set('test_set_with_expiry', v + 2, now)
    @client.set('test_set_with_expiry', v)
    sleep(1.0)
    expect(@client.get('test_set_with_expiry')).to eql(v)
  end

  it "should have age stat" do
    now = Time.now.to_i
    @client.set('test_age', 'nibbler')
    sleep(1.0)
    expect(@client.get('test_age')).to eql('nibbler')

    stats = @client.stats['127.0.0.1:22133']
    expect(stats.has_key?('queue_test_age_age')).to be_truthy
    expect(stats['queue_test_age_age'] >= 1000).to be_truthy
  end

  it "should rotate log" do
    log_rotation_path = File.join(@tmp_path, 'test_log_rotation')

    Dir.glob("#{log_rotation_path}*").each do |file|
      File.unlink(file) rescue nil
    end
    expect(@client.get('test_log_rotation')).to be_nil

    v = 'x' * 8192

    @client.set('test_log_rotation', v)
    expect(File.size(log_rotation_path)).to eql(8213)
    @client.get('test_log_rotation')

    expect(@client.get('test_log_rotation')).to be_nil

    @client.set('test_log_rotation', v)
    expect(@client.get('test_log_rotation')).to eql(v)

    expect(File.size(log_rotation_path)).to eql(1)
    # rotated log should be erased after a successful roll.
    expect(Dir.glob("#{log_rotation_path}*").size).to eql(1)
  end

  it "should output statistics per server" do
    stats = @client.stats
    stats.kind_of? Hash
    expect(stats.has_key?('127.0.0.1:22133')).to be_truthy

    server_stats = stats['127.0.0.1:22133']

    basic_stats = %w( bytes pid time limit_maxbytes cmd_get version
                      bytes_written cmd_set get_misses total_connections
                      curr_connections curr_items uptime get_hits total_items
                      rusage_system rusage_user bytes_read )

    basic_stats.each do |stat|
      expect(server_stats.has_key?(stat)).to be_truthy
    end
  end

  it "should return valid response with unkown command" do
    #why is this an unknown command?
    expect {
      response = @client.add('blah', 1)
    }.to raise_error(MemCache::MemCacheError)
  end

  it "should disconnect and reconnect again" do
    v = rand(2**32-1)
    @client.set('test_that_disconnecting_and_reconnecting_works', v)
    @client.reset
    expect(@client.get('test_that_disconnecting_and_reconnecting_works')).to eql(v)
  end

  it "should use epoll on linux" do
    # this may take a few seconds.
    # the point is to make sure that we're using epoll on Linux, so we can
    # handle more than 1024 connections.

    unless IO::popen("uname").read.chomp == "Linux"
      skip "skipping epoll test: not on Linux"
    end

    fd_limit = IO::popen("bash -c 'ulimit -n'").read.chomp.to_i
    unless fd_limit > 1024
      skip "skipping epoll test: 'ulimit -n' = #{fd_limit}, need > 1024"
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
      expect(client.get('test_epoll')).to eql(v)
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

    expect {
      StarlingServer::QueueCollection.new(invalid_path)
    }.to raise_error(StarlingServer::InaccessibleQueuePath)
  end

  after do
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    @client.reset
    FileUtils.rm(Dir.glob(File.join(@tmp_path, '*')))
  end
end
