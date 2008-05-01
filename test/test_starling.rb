require File.join(File.dirname(__FILE__), 'test_helper.rb')

require 'starling/server'

require 'fileutils'
require 'rubygems'
require 'memcache'

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


class TestStarling < Test::Unit::TestCase

  def setup
    begin
      Dir::mkdir(tmp_path)
    rescue Errno::EEXIST
    end

    @server_pid = safely_fork do
      server = StarlingServer::Base.new(:host => '127.0.0.1',
                                        :port => 22133,
                                        :path => tmp_path,
                                        :logger => Logger.new(STDERR),
                                        :log_level => Logger::FATAL)
      Signal.trap("INT") { server.stop }
      Process.kill("USR1", Process.ppid)
      server.run
    end

    @client = MemCache.new('127.0.0.1:22133')
  end

  def teardown
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    @client.reset
    FileUtils.rm(Dir.glob(File.join(tmp_path, '*')))
  end
  
  def test_temporary_path_exists_and_is_writable
    assert File.exist?(tmp_path)
    assert File.directory?(tmp_path)
    assert File.writable?(tmp_path)
  end

  def test_set_and_get_one_entry
    v = rand((2**32)-1)
    assert_equal nil, @client.get('test_set_and_get_one_entry')
    @client.set('test_set_and_get_one_entry', v)
    assert_equal v, @client.get('test_set_and_get_one_entry')
  end

  def test_set_with_expiry
    v = rand((2**32)-1)
    assert_equal nil, @client.get('test_set_with_expiry')
    now = Time.now.to_i
    @client.set('test_set_with_expiry', v + 2, now)
    @client.set('test_set_with_expiry', v)
    sleep(1.0)
    assert_equal v, @client.get('test_set_with_expiry')
  end

  def test_age
    now = Time.now.to_i
    @client.set('test_age', 'nibbler')
    sleep(1.0)
    assert_equal 'nibbler', @client.get('test_age')

    stats = @client.stats['127.0.0.1:22133']
    puts stats.inspect
    assert stats.has_key?('queue_test_age_age')
    assert stats['queue_test_age_age'] >= 1000
  end
  
  def test_log_rotation
    log_rotation_path = File.join(tmp_path, 'test_log_rotation')

    Dir.glob("#{log_rotation_path}*").each do |file|
      File.unlink(file) rescue nil
    end
    assert_equal nil, @client.get('test_log_rotation')

    v = 'x' * 8192

    @client.set('test_log_rotation', v)
    assert_equal 8207, File.size(log_rotation_path)
    @client.get('test_log_rotation')

    assert_equal nil, @client.get('test_log_rotation')

    @client.set('test_log_rotation', v)
    assert_equal v, @client.get('test_log_rotation')

    assert_equal 1, File.size(log_rotation_path)
    # rotated log should be erased after a successful roll.
    assert_equal 1, Dir.glob("#{log_rotation_path}*").size
  end

  def test_stats
    stats = @client.stats
    assert_kind_of Hash, stats
    assert stats.has_key?('127.0.0.1:22133')
    
    server_stats = stats['127.0.0.1:22133']
    
    basic_stats = %w( bytes pid time limit_maxbytes cmd_get version
                      bytes_written cmd_set get_misses total_connections
                      curr_connections curr_items uptime get_hits total_items
                      rusage_system rusage_user bytes_read )

    basic_stats.each do |stat|
      assert server_stats.has_key?(stat)
    end
  end

  def test_unknown_command_returns_valid_result
    response = @client.add('blah', 1)
    assert_match 'CLIENT_ERROR', response
  end

  def test_that_disconnecting_and_reconnecting_works
    v = rand(2**32-1)
    @client.set('test_that_disconnecting_and_reconnecting_works', v)
    @client.reset
    assert_equal v, @client.get('test_that_disconnecting_and_reconnecting_works')
  end
  
  def test_epoll
    # this may take a few seconds.
    # the point is to make sure that we're using epoll on Linux, so we can
    # handle more than 1024 connections.
    
    unless IO::popen("uname").read.chomp == "Linux"
      puts "(Skipping epoll test: not on Linux)"
      return
    end
    fd_limit = IO::popen("bash -c 'ulimit -n'").read.chomp.to_i
    unless fd_limit > 1024
      puts "(Skipping epoll test: 'ulimit -n' = #{fd_limit}, need > 1024)"
      return
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
      assert_equal v, client.get('test_epoll')
    ensure
      Process.kill("TERM", pid1)
      Process.kill("TERM", pid2)
    end
  end
  

  private

  def tmp_path
    File.join(File.dirname(__FILE__), "..", "tmp")
  end
end
