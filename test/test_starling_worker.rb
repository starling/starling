$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'rubygems'
require 'fileutils'
require 'memcache'
require 'digest/md5'

require 'starling/server'
require 'starling/client'
require 'starling/worker'

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

describe "StarlingWorker" do
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
    
    @worker = StarlingWorker::Base.new(@client.starling)
  end
  
  it "should add and remove messages from local queue" do
    @worker.add_message_to_local_queue("message").should be_true
    @worker.get_message_from_local_queue.should eql("message")
  end
  
  it "should add and remove messages from remote queue" do
    @worker.add_message_to_remote_queue("message").should be_true
    @worker.get_message_from_remote_queue.should eql("message")
  end
  
  it "should have starling" do
    @worker.should be_connected_to_starling
  end
  
  it "should have a queue name" do
    @worker.queue_name.should eql("starling_worker_base")
  end
  
  it "should have threadpool size" do
    @worker.threadpool.should_not be_nil
  end
  
  it "should be able to process"
  
  after do
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    FileUtils.rm(Dir.glob(File.join(@tmp_path, '*')))
  end
end