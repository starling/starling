require File.expand_path('../spec_helper', __FILE__)

class FakeBackingQueue < Array
  def consume_log_into(other)
    MAX_PRIMARY_SIZE.times do
      if v = shift
        other.push v
      end
    end
  end
end

describe "StarlingServer::DiskBackedQueueWithPersistentQueueBuffer" do
  before do
    @primary_queue = []
    @backing_queue = FakeBackingQueue.new
    @queue = StarlingServer::DiskBackedQueueWithPersistentQueueBuffer.new(@primary_queue, @backing_queue)
  end

  it "should refer the first #{MAX_PRIMARY_SIZE} to the primary queue" do
    MAX_PRIMARY_SIZE.times do
      @queue.push "hello"
    end
    @primary_queue.length.should == MAX_PRIMARY_SIZE
    @backing_queue.should be_empty
  end

  it "should refer the #{MAX_PRIMARY_SIZE+1}th message to the backing queue" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end
    @primary_queue.length.should == MAX_PRIMARY_SIZE
    @backing_queue.length.should == 1
  end

  it "should pop messages off the primary first" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end

    @queue.pop

    @primary_queue.length.should == MAX_PRIMARY_SIZE - 1
    @backing_queue.length.should == 1
  end

  it "should pop messages off the backing queue once the primary is empty" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end

    MAX_PRIMARY_SIZE.times{ @queue.pop }

    @primary_queue.should be_empty
    @backing_queue.should_not be_empty

    @queue.pop.should == "hello"
    @queue.empty?
  end

  it "should total both the lengths" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end
    @queue.length.should == MAX_PRIMARY_SIZE+1
  end
end
