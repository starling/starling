module StarlingWorker
  
  class Gettingdata < StarlingWorker::Base
    def initialize(opts = {})
      @opts = {
        :incoming_remote_queue_name => 'gettingdata_out'
      }.merge(opts)
      
      super(@opts)
    end
        
    def process(message)
      raise "no message" unless message
    end
  end
  
end