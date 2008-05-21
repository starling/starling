Gem::Specification.new do |s|
	s.name = "starling"
	s.version = "0.9.7.5"
	s.authors = ["Blaine Cook", "Chris Wanstrath", "anotherbritt", "Glenn Rempe", "Abdul-Rahman Advany"]
	s.email = ["blaine@twitter.com", "chris@ozmm.org", "abdulrahman@advany.com"]
	s.homepage = "http://github.com/fiveruns/starling/"
	s.summary = "Starling is a lightweight, transactional, distributed queue server"
	s.description = s.summary

	s.require_path = 'lib'
	s.executables = ["starling", "starling_client", "starling_top"]

	# get this easily and accurately by running 'Dir.glob("{lib,test}/**/*")'
	# in an IRB session.  However, GitHub won't allow that command hence
	# we spell it out.
	s.files = ["README.rdoc", "LICENSE", "CHANGELOG", "Rakefile", "lib/starling/handler.rb", "lib/starling/persistent_queue.rb", "lib/starling/queue_collection.rb", "lib/starling/server_runner.rb", "lib/starling/server.rb", "lib/starling/client_runner.rb", "lib/starling/client.rb", "lib/starling/worker.rb", "lib/starling/thread_pool.rb", "lib/starling.rb", "etc/starling.redhat", "etc/starling.ubuntu"]
	s.test_files = ["test/test_starling_server.rb", "test/test_starling_client.rb", "test/test_starling_worker.rb"]

	s.has_rdoc = true
	s.rdoc_options = ["--quiet", "--title", "starling documentation", "--opname", "index.html", "--line-numbers", "--main", "README.rdoc", "--inline-source"]
	s.extra_rdoc_files = ["README.rdoc", "CHANGELOG", "LICENSE"]

	s.add_dependency 'fiveruns-memcache-client'
	s.add_dependency 'SyslogLogger'
end
