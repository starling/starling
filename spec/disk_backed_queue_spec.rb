require File.expand_path('../spec_helper', __FILE__)

MAX_LOGFILE_SIZE = StarlingServer::DiskBackedQueue::MAX_LOGFILE_SIZE
TOO_MUCH_DATA = (0..MAX_LOGFILE_SIZE).map{|v| v.to_s}
describe "StarlingServer::DiskBackedQueue" do
  before do
    @tmp_path = File.join(File.dirname(__FILE__), "tmp")
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
  end

  it "should push messages" do
    @queue.length.should == 0
    @queue.push("message")
    @queue.length.should == 1
  end

  it "should consume itself in order" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    output_array = []
    @queue.consume_log_into(output_array)
    output_array.should == TOO_MUCH_DATA[0...MAX_LOGFILE_SIZE]
    @queue.consume_log_into(output_array)
    output_array.should == TOO_MUCH_DATA
  end

  it "should know if it's empty? or any?" do
    @queue.empty?.should == true
    @queue.any?.should == false

    @queue.push "a"

    @queue.empty?.should == false
    @queue.any?.should == true

    @queue.consume_log_into([])

    @queue.empty?.should == true
    @queue.any?.should == false
  end

  it "should purge" do
    @queue.push "a"
    @queue.should_not be_empty
    @queue.purge
    @queue.should be_empty
    @queue.consume_log_into(array = [])
    array.should be_empty
  end

  it "should know it's total items" do
    @queue.push "a"
    @queue.purge
    @queue.should be_empty
    @queue.push "a"
    @queue.total_items.should == 2
  end

  it "should report logsize as the size on disk of the queue" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    header_size = StarlingServer::DiskBackedQueue::LOGGED_MESSAGE_HEADER_LENGTH
    @queue.logsize.should == header_size * TOO_MUCH_DATA.size + TOO_MUCH_DATA.to_s.size
  end

  it "should report logsize as the size on disk of the queue even after a reload" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
    header_size = StarlingServer::DiskBackedQueue::LOGGED_MESSAGE_HEADER_LENGTH
    @queue.logsize.should == header_size * TOO_MUCH_DATA.size + TOO_MUCH_DATA.to_s.size
  end

  it "should know how long it is" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    @queue.length.should == TOO_MUCH_DATA.size
  end

  it "should know how long it is even after a restart" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
    @queue.length.should == TOO_MUCH_DATA.size
  end

  it "should restore itself" do
    TOO_MUCH_DATA.each{|v| @queue.push v }

    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")

    @queue.consume_log_into(output_array = [])
    @queue.consume_log_into(output_array)
    output_array.should == TOO_MUCH_DATA
  end

  after do
    FileUtils.rm_r(@tmp_path)
  end
end
