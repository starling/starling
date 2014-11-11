require 'spec_helper'

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

    expect(@primary_queue.length).to eq MAX_PRIMARY_SIZE
    expect(@backing_queue).to be_empty
  end

  it "should refer the #{MAX_PRIMARY_SIZE+1}th message to the backing queue" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end

    expect(@primary_queue.length).to eq MAX_PRIMARY_SIZE
    expect(@backing_queue.length).to eq 1
  end

  it "should pop messages off the primary first" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end

    @queue.pop

    expect(@primary_queue.length).to eq(MAX_PRIMARY_SIZE - 1)
    expect(@backing_queue.length).to eq 1
  end

  it "should pop messages off the backing queue once the primary is empty" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end

    MAX_PRIMARY_SIZE.times{ @queue.pop }

    expect(@primary_queue).to be_empty
    expect(@backing_queue).to_not be_empty

    expect(@queue.pop).to eq "hello"
    expect(@queue).to be_empty
  end

  it "should total both the lengths" do
    (MAX_PRIMARY_SIZE+1).times do
      @queue.push "hello"
    end
    expect(@queue.length).to eq MAX_PRIMARY_SIZE+1
  end
end
