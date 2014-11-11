$:.unshift(File.join(File.dirname(__FILE__), "..", "lib"))

require 'rubygems'
require 'fileutils'
require 'memcache'
require 'digest/md5'
require 'starling'

require 'starling/server'

class StarlingServer::PersistentQueue
  remove_const :SOFT_LOG_MAX_SIZE
  SOFT_LOG_MAX_SIZE = 16 * 1024 # 16 KB
end

class StarlingServer::DiskBackedQueueWithPersistentQueueBuffer
  remove_const :MAX_PRIMARY_SIZE
  MAX_PRIMARY_SIZE = 10
end

class StarlingServer::DiskBackedQueue
  remove_const :MAX_LOGFILE_SIZE
  MAX_LOGFILE_SIZE = 10
end

MAX_PRIMARY_SIZE = StarlingServer::DiskBackedQueueWithPersistentQueueBuffer::MAX_PRIMARY_SIZE
MAX_LOGFILE_SIZE = StarlingServer::DiskBackedQueue::MAX_LOGFILE_SIZE

def safely_fork(&block)
  # anti-race juice:
  blocking = true
  Signal.trap("USR1") { blocking = false }

  pid = Process.fork(&block)

  while blocking
    sleep 0.1
  end

  pid
end
