require 'thread'

module StarlingServer
  class DiskBackedQueue
    MAX_LOGFILE_SIZE = 10_000
    LOGGED_MESSAGE_HEADER_LENGTH = [1].pack("I").size
    QUEUE_MUTEX = Mutex.new

    attr_reader :total_items

    def initialize(persistence_path, queue_name)
      @persistence_path, @queue_name = persistence_path, queue_name
      @active_log_file_name = latest_log_file
      data = load_log(@active_log_file_name)
      @active_log_file_size = data.size
      @total_items = 0
      if @active_log_file_name.nil?
        @active_log_file_name = new_logfile_name
        FileUtils.mkdir_p(File.dirname(@active_log_file_name))
      end
      @active_log_file = File.open(@active_log_file_name, "ab")
    end

    def any?
      @active_log_file_size > 0 or available_log_files.size > 1
    end

    def empty?
      !any?
    end

    def length
      (available_log_files.size - 1) * MAX_LOGFILE_SIZE + @active_log_file_size
    end

    def logsize
      available_log_files.inject(0){|sum, f| sum + File.size(f) }
    end

    def push(data)
      QUEUE_MUTEX.synchronize do
        rotate! if @active_log_file_size >= MAX_LOGFILE_SIZE
        @active_log_file << [data.size].pack("I") + data
        @active_log_file.flush
        @active_log_file_size += 1
        @total_items += 1
      end
    end

    def consume_log_into(queue)
      QUEUE_MUTEX.synchronize do
        return unless file = first_log_file
        return if @active_log_file_name == file and @active_log_file_size.zero?

        rotate! if @active_log_file_name == file

        load_log(file){|i| queue.push(i) }
        File.unlink(file)
      end
    end

    def close
      @active_log_file.close if @active_log_file
      @active_log_file = nil
    end

    def initial_bytes
      logsize - length * LOGGED_MESSAGE_HEADER_LENGTH
    end

    def purge
      close
      FileUtils.rm_r( File.join(@persistence_path, "disk_backed_queue", @queue_name) )
      @active_log_file_size = 0
      rotate!
    end

  protected

    def available_log_files
      Dir[File.join(@persistence_path, "disk_backed_queue", @queue_name, "*")].sort
    end

    def rotate!
      close
      @active_log_file_name = new_logfile_name
      @active_log_file_size = 0
      FileUtils.mkdir_p(File.dirname(@active_log_file_name))
      @active_log_file = File.open(@active_log_file_name, "ab")
    end

    def new_logfile_name(suffix = 0)
      name = File.join(@persistence_path, "disk_backed_queue", @queue_name, "%s-%03i" % [Time.now.to_i, suffix])
      if File.exists?( name )
        new_logfile_name(suffix + 1)
      else
        name
      end
    end

    def latest_log_file
      available_log_files.last
    end

    def first_log_file
      available_log_files.first
    end

    def load_log(file, &block)
      return [] unless file
      data = []
      File.open(file){|f|
        while raw_size = f.read(LOGGED_MESSAGE_HEADER_LENGTH)
          next unless raw_size
          size = raw_size.unpack("I").first
          item = f.read(size)
          if block_given?
            yield item
          else
            data << item
          end
        end
      }
      data
    end
  end
end
