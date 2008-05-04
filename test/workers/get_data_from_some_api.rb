module StarlingWorker
  
  class GetDataFromSomeApi < StarlingWorker::Base
    def initialize(opts = {})
      @opts = {
       :incoming_remote_queue_name => 'get_data_from_some_api_out'
      }.merge(opts)
      
      super(@opts)
    end
    
    def process(message)
      raise "no message" unless message
    end
  end
  
end