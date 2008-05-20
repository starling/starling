GEM       = "starling"
VER       = "0.9.7.5"
AUTHORS    = ["Blaine Cook", "Chris Wanstrath", "anotherbritt", "Glenn Rempe", "Abdul-Rahman Advany"]
EMAILS     = ["blaine@twitter.com", "chris@ozmm.org", "abdulrahman@advany.com"]
HOMEPAGE  = "http://github.com/advany/starling/"
SUMMARY   = "Starling is a lightweight, transactional, distributed queue server"

spec = Gem::Specification.new do |s|
	s.name = GEM
	s.version = VER
	s.authors = AUTHORS
	s.email = EMAILS
	s.homepage = HOMEPAGE
	s.summary = SUMMARY
	s.description = s.summary

	s.require_path = 'lib'
	s.executables = ["starling", "starling_client"]

	# get this easily and accurately by running 'Dir.glob("{lib,test}/**/*")'
	# in an IRB session.  However, GitHub won't allow that command hence
	# we spell it out.
	s.files = ["README.rdoc", "LICENSE", "CHANGELOG", "Rakefile", "lib/starling", "lib/starling/handler.rb", "lib/starling/persistent_queue.rb", "lib/starling/queue_collection.rb", "lib/starling/server_runner.rb", "lib/starling/server.rb", "lib/starling/client_runner.rb", "lib/starling/client.rb", "lib/starling/worker.rb", "lib/starling/thread_pool.rb", "lib/starling.rb", "test/test_starling_server.rb", "test/test_starling_client.rb", "test/test_starling_worker.rb"]
	s.test_files = ["test/test_starling_server.rb", "test/test_starling_client.rb", "test/test_starling_worker.rb"]

	s.has_rdoc = true
	s.rdoc_options = ["--quiet", "--title", "starling documentation", "--opname", "index.html", "--line-numbers", "--main", "README.rdoc", "--inline-source"]
	s.extra_rdoc_files = ["README.rdoc", "CHANGELOG", "LICENSE"]

	s.add_dependency 'memcache-client'
end
