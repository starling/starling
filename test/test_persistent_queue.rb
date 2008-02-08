require File.join(File.dirname(__FILE__), 'test_helper.rb')

require 'digest/md5'
require 'starling/server'

class TestQueueCollection < Test::Unit::TestCase
  def test_creating_queue_collection_with_invalid_path_throws_inaccessible_queue_exception
    invalid_path = nil
    while invalid_path.nil? || File.exist?(invalid_path)
      invalid_path = File.join('/', Digest::MD5.hexdigest(rand(2**32-1).to_s)[0,8])
    end

    assert_raises(StarlingServer::InaccessibleQueuePath) {
      StarlingServer::QueueCollection.new(invalid_path)
    }
  end
end
