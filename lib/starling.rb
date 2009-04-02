require 'memcache'

class Starling < MemCache

  WAIT_TIME = 0.25
  alias_method :_original_get, :get
  alias_method :_original_delete, :delete

  ##
  # fetch an item from a queue.

  def get(*args)
    loop do
      response = _original_get(*args)
      return response unless response.nil?
      sleep WAIT_TIME
    end
  end
  
  ##
  # will return the next item or nil

  def fetch(*args)
    _original_get(*args)
  end

  ##
  # Delete the key (queue) from all Starling servers. This is necessary
  # because the random way a server is chosen in #get_server_for_key
  # implies that the queue could easily be spread across the entire
  # Starling cluster.

  def delete(key, expiry = 0)
    with_servers do
      _original_delete(key, expiry)
    end
  end

  ##
  # Provides a way to work with a specific list of servers by
  # forcing all calls to #get_server_for_key to use a specific
  # server, and changing that server each time that the call
  # yields to the block provided.  This helps work around the
  # normally random nature of the #get_server_for_key method.
  #
  def with_servers(my_servers = self.servers.dup)
    return unless block_given?
    my_servers.each do |server|
      yield
    end
  end
  
  ##
  # insert +value+ into +queue+.
  #
  # +expiry+ is expressed as a UNIX timestamp
  #
  # If +raw+ is true, +value+ will not be Marshalled. If +raw+ = :yaml, +value+
  # will be serialized with YAML, instead.

  def set(queue, value, expiry = 0, raw = false)
    retries = 0
    begin
      if raw == :yaml
        value = YAML.dump(value)
        raw = true
      end

      super(queue, value, expiry, raw)
    rescue MemCache::MemCacheError => e
      retries += 1
      sleep WAIT_TIME
      retry unless retries > 3
      raise e
    end
  end

  ##
  # returns the number of items in +queue+. If +queue+ is +:all+, a hash of all
  # queue sizes will be returned.

  def sizeof(queue, statistics = nil)
    statistics ||= stats

    if queue == :all
      queue_sizes = {}
      available_queues(statistics).each do |queue|
        queue_sizes[queue] = sizeof(queue, statistics)
      end
      return queue_sizes
    end

    statistics.inject(0) { |m,(k,v)| m + v["queue_#{queue}_items"].to_i }
  end

  ##
  # returns a list of available (currently allocated) queues.

  def available_queues(statistics = nil)
    statistics ||= stats

    statistics.map { |k,v|
      v.keys
    }.flatten.uniq.grep(/^queue_(.*)_items/).map { |v|
      v.gsub(/^queue_/, '').gsub(/_items$/, '')
    }.reject { |v|
      v =~ /_total$/ || v =~ /_expired$/
    }
  end

  ##
  # iterator to flush +queue+. Each element will be passed to the provided
  # +block+

  def flush(queue)
    sizeof(queue).times do
      v = get(queue)
      yield v if block_given?
    end
  end

  private

  def get_server_for_key(key)
    raise ArgumentError, "illegal character in key #{key.inspect}" if key =~ /\s/
    raise ArgumentError, "key too long #{key.inspect}" if key.length > 250
    raise MemCacheError, "No servers available" if servers.empty?
 
    # Ignores server weights, oh well
    srvs = servers.dup
    srvs.size.times do |try|
      n = rand(srvs.size)
      server = srvs[n]
      return server if server.alive?
      srvs.delete_at(n)
    end
  
    raise MemCacheError, "No servers available (all dead)"
  end
end