$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'rubygems'
require 'spec'
require 'fileutils'
require 'memcache'
require 'digest/md5'

require 'starling/server'
require 'starling/client'

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
    @templates_path = File.join(File.dirname(__FILE__), "templates")
    @workers_path = File.join(File.dirname(__FILE__), "workers")
    
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
      Signal.trap("INT") { server.stop }
      Process.kill("USR1", Process.ppid)
      server.run
    end
    
    @client = StarlingClient::Base.new(:host => '127.0.0.1',
                                       :port => 22133,
                                       :templates_path => @templates_path,
                                       :workers_path => @workers_path)
  end
  
  it "should test if tmp_path exists and is writeable" do
    File.exist?(@tmp_path).should be_true
    File.directory?(@tmp_path).should be_true
    File.writable?(@tmp_path).should be_true
  end
  
  it "should test if templates_path exists and is writeable" do
    File.exist?(@templates_path).should be_true
    File.directory?(@templates_path).should be_true
    File.writable?(@templates_path).should be_true
  end
  
  it "should test if workers_path exists and is writeable" do
    File.exist?(@workers_path).should be_true
    File.directory?(@workers_path).should be_true
    File.writable?(@workers_path).should be_true
  end
  
  it "should load templates" do
    @client.load_templates.should eql(["ActiveRecord", "Basic"])
  end
  
  it "should load workers" do
    @client.load_workers.should eql(["GetDataFromSomeApi", "Gettingdata"])
  end
  
  it "should return Starling" do
    @client.starling.should_not == nil
  end
  
  after do
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    FileUtils.rm(Dir.glob(File.join(@tmp_path, '*')))
  end
end