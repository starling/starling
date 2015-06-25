require 'spec_helper'

TOO_MUCH_DATA = (0..MAX_LOGFILE_SIZE).map{|v| v.to_s}

describe StarlingServer::DiskBackedQueue do
  before do
    @tmp_path = File.join(File.dirname(__FILE__), "tmp")
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
  end

  it "should push messages" do
    expect(@queue.length).to eq 0
    @queue.push("message")
    expect(@queue.length).to eq 1
  end

  it "should consume itself in order" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    output_array = []
    @queue.consume_log_into(output_array)
    expect(output_array).to eq TOO_MUCH_DATA[0...MAX_LOGFILE_SIZE]
    @queue.consume_log_into(output_array)
    expect(output_array).to eq TOO_MUCH_DATA
  end

  it "should know if it's empty? or any?" do
    expect(@queue).to be_empty
    expect(@queue.any?).to be_falsey

    @queue.push "a"

    expect(@queue).to_not be_empty
    expect(@queue.any?).to be_truthy

    @queue.consume_log_into([])

    expect(@queue).to be_empty
    expect(@queue.any?).to be_falsey
  end

  it "should purge" do
    @queue.push "a"
    expect(@queue).to_not be_empty
    @queue.purge
    expect(@queue).to be_empty
    @queue.consume_log_into(array = [])
    expect(array).to be_empty
  end

  it "should know it's total items" do
    @queue.push "a"
    @queue.purge
    expect(@queue).to be_empty
    @queue.push "a"
    expect(@queue.total_items).to eq 2
  end

  it "should report logsize as the size on disk of the queue" do
    TOO_MUCH_DATA.each{ |v| @queue.push v }
    header_size = StarlingServer::DiskBackedQueue::LOGGED_MESSAGE_HEADER_LENGTH
    expect(@queue.logsize).to eq(header_size * TOO_MUCH_DATA.size + TOO_MUCH_DATA.reduce(&:+).size)
  end

  it "should report logsize as the size on disk of the queue even after a reload" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
    header_size = StarlingServer::DiskBackedQueue::LOGGED_MESSAGE_HEADER_LENGTH
    expect(@queue.logsize).to eq(header_size * TOO_MUCH_DATA.size + TOO_MUCH_DATA.reduce(&:+).size)
  end

  it "should know how long it is" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    expect(@queue.length).to eq TOO_MUCH_DATA.size
  end

  it "should know how long it is even after a restart" do
    TOO_MUCH_DATA.each{|v| @queue.push v }
    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")
    expect(@queue.length).to eq TOO_MUCH_DATA.size
  end

  it "should restore itself" do
    TOO_MUCH_DATA.each{|v| @queue.push v }

    @queue = StarlingServer::DiskBackedQueue.new(@tmp_path, "disk_backed_queue")

    @queue.consume_log_into(output_array = [])
    @queue.consume_log_into(output_array)
    expect(output_array).to eq TOO_MUCH_DATA
  end

  after do
    FileUtils.rm_r(@tmp_path)
  end
end
