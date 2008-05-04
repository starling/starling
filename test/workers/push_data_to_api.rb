module StarlingWorker
  
  class PushDataToApi < StarlingWorker::Base
    def initialize(opts = {})
      @opts = {
        :outgoing_remote_queue_name => 'push_data_to_api_out', 
        :threads => 1
      }.merge(opts)
      
      super(@opts)
    end
        
    def process
      sleep 0.1
      "hoi"
    end
  end
  
end