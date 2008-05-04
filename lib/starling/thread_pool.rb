# http://en.wikipedia.org/wiki/Thread_pool_pattern
class ThreadPool

  # 1. Initialize with arbitrary number of threads 
  def initialize( threads_number = 1, &exception_handler )
    @work_queue = Queue.new
    @worker_threads = ThreadGroup.new

    # Create all threads in advance: that's the thread pool after all
    threads_number.times do

      worker_thread = Thread.new do
        # Body of the Worker Thread
        begin
          work_to_do = @work_queue.pop() # Blocking
          break if work_to_do == :END_OF_WORK
          begin
            work_to_do.block.call( *work_to_do.args )
          rescue Exception => e # Since they are swallowed by default
            if !exception_handler.nil?
              yield e
            else
              # Standard exception handling
              dump = "Worker Thread thrown an exception:\n"
              dump += "#{e.message}\n(#{e.class.name})\n"
              dump += e.backtrace().join( "\n" ) + "\n"
              print dump
            end
          end
        end until false
        # Worker thread ends up gracefully <img src='http://ruby-rails.pl/wp-includes/images/smilies/icon_smile.gif' alt=':)' class='wp-smiley' /> 
      end

      @worker_threads.add worker_thread 
    end
  end
  
  # 2. Add job to the queue, example:
  def add_work( *args, &block )
    @work_queue.push( Runnable.new( args, &block ) )
  end

  # 3. Allow working threads to end up after finishing all queued work
  def no_more_work
    threads_n = @worker_threads.list.length
    threads_n.times { @work_queue.push :END_OF_WORK }
  end

  # 4. Wait for all work to finish
  def join
    @worker_threads.list.each { |t| t.join }
  end
  
end