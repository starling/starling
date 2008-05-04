module StarlingWorker
  
  class GetDataFromSomeApi < StarlingWorker::Base
    def initialize(opts = {})
      @opts = {
       :incoming_remote_queue_name => 'push_data_to_api_out', 
       :threads => 1
      }.merge(opts)
      
      super(@opts)
    end
    
    def process(message)
      sleep 0.1
      raise "no message" unless message
    end
  end
  
end