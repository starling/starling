module StarlingWorker
  
  class GetDataFromSomeApi < Base
    def process(message)
      raise "no message" unless message
    end
  end
  
end