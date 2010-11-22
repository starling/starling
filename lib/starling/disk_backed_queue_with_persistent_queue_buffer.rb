require 'starling/disk_backed_queue'
require 'starling/persistent_queue'

module StarlingServer
  class DiskBackedQueueWithPersistentQueueBuffer
    MAX_PRIMARY_SIZE = 10_000
    def initial_bytes
      @primary.initial_bytes + @backing.initial_bytes
    end

    def total_items
      @primary.total_items + @backing.total_items
    end

    def current_age
      @primary.current_age
    end

    def logsize
      @primary.logsize
    end

    def backing_logsize
      @backing.logsize
    end

    def length
      @primary.length + @backing.length
    end

    def primary_length
      @primary.length
    end

    def backing_length
      @backing.length
    end

    def initialize(primary, backing)
      @primary = primary
      @backing = backing
    end

    def push(data)
      if should_go_to_backing?
        @backing.push(data)
      else
        @primary.push(data)
      end
    end

    def purge
      @primary.purge
      @backing.purge
    end

    def empty?
      @primary.empty? and @backing.empty?
    end

    def pop
      @backing.consume_log_into(@primary) if @primary.empty?
      @primary.pop
    end

    def close
      @primary.close
      @backing.close
    end

  protected
    def should_go_to_backing?
      return true if @primary.length >= MAX_PRIMARY_SIZE
      @backing.any?
    end
  end
end
