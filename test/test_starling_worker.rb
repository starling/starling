$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'rubygems'
require 'spec'
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
                                       
    @client.load_templates
    @client.load_workers
    
    @worker = StarlingWorker::Base.new(:host => '127.0.0.1',
                                       :port => 22133,
                                       :continues_processing => false)
                                       
    @starling = @client.starling
  end
  
  it "should add and remove messages from local queue" do
    @worker.add_message_to_local_queue("message").should be_true
    @worker.local_queue.size.should eql(1)
    @worker.get_message_from_local_queue.should eql("message")
  end
  
  it "should add and remove messages from remote queue" do
    @worker.add_message_to_incoming_remote_queue("message").should be_true
    @worker.get_message_from_incoming_remote_queue.should eql("message")
    
    Thread.new do
      @worker.get_message_from_outgoing_remote_queue.should eql("test")
    end
    sleep 0.1
    @worker.add_message_to_outgoing_remote_queue("test")
  end
  
  it "should have a remote queue name" do
    @worker.incoming_remote_queue_name.should eql("starling_worker_base_in")
    @worker.outgoing_remote_queue_name.should eql("starling_worker_base_out")
  end
  
  it "should have threadpool size" do
    @worker.threadpool.should_not be_nil
  end
  
  it "should pass from remote queue to process" do
    @worker.add_message_to_incoming_remote_queue("test")
    @worker.from_remote_queue_to_process.should eql("test")
  end
  
  it "should pass from local queue to remote queue" do
    @worker.add_message_to_local_queue("test")
    
    @worker.from_local_queue_to_remote_queue
    
    @starling.sizeof(@worker.outgoing_remote_queue_name).should eql(1)
    
    @worker.get_message_from_outgoing_remote_queue.should eql("test")
    
    @starling.sizeof(@worker.outgoing_remote_queue_name).should eql(0)
  end
  
  it "should process message with block and add to local queue" do
    @worker.process_message("test") do |message|
      message.should eql("test")
      message
    end
    
    @worker.get_message_from_local_queue.should eql("test")
  end
  
  it "should be able to enq_thread with block" do
    @worker.add_message_to_incoming_remote_queue("test")
    
    @worker.process_message_from_incoming_remote_queue do |message|
      message.should eql("test")
      message
    end
    
    @worker.get_message_from_local_queue.should eql("test")
  end
  
  it "should be able to deq_thread with block" do
    @worker.add_message_to_local_queue("test")
    
    @worker.process_message_from_local_queue_to_outgoing_remote_queue
    
    @worker.get_message_from_outgoing_remote_queue.should eql("test")
  end
  
  it "should process worker" do
    @worker.add_message_to_incoming_remote_queue("**")
    
    @worker.process do |message|
      message.should eql("**")
      message
    end
    
    @worker.run
    
    @starling.sizeof(@worker.outgoing_remote_queue_name).should eql(1)
  end
  
  it "should pass from process to local queue" do
    @worker.from_process_to_local_queue("test")
    @worker.get_message_from_local_queue.should eql("test")
  end
  
  it "should run worker that implemented process" do
    @worker.add_message_to_incoming_remote_queue("**")
    worker = StarlingWorker::Gettingdata.new(:host => '127.0.0.1',
                                             :port => 22133,
                                             :continues_processing => false)
    worker.run
  end
  
  after do
    Process.kill("INT", @server_pid)
    Process.wait(@server_pid)
    FileUtils.rm(Dir.glob(File.join(@tmp_path, '*')))
  end
end