require File.join(File.dirname(__FILE__), 'test_helper.rb')

require 'starling/server'

require 'fileutils'
require 'rubygems'
require 'memcache'

class StarlingServer::PersistentQueue
  remove_const :SOFT_LOG_MAX_SIZE
  SOFT_LOG_MAX_SIZE = 16 * 1024 # 16 KB
end

class TestStarling < Test::Unit::TestCase

  def setup
    @server, @acceptor = StarlingServer::Base.start(:host => '127.0.0.1',
                                                    :port => 22133,
                                                    :path => tmp_path)

    @client = MemCache.new('127.0.0.1:22133')
  end

  def teardown
    @server.stop
    @client.reset
    FileUtils.rm_f(File.join(tmp_path, '*'))
    sleep 0.01
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
    sleep(now + 1 - Time.now.to_f)
    assert_equal v, @client.get('test_set_with_expiry')
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
    assert_equal 2, Dir.glob("#{log_rotation_path}*").size
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

  private

  def tmp_path
    File.join(File.dirname(__FILE__), "..", "tmp")
  end
end
