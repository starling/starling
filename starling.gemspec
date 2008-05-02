$SAFE = 3

GEM       = "starling"
VER       = "0.9.5.4"
AUTHORS    = ["Blaine Cook", "anotherbritt"]
EMAILS     = ["blaine@twitter.com"]
HOMEPAGE  = "http://github.com/anotherbritt/starling/"
SUMMARY   = "Starling is a lightweight, transactional, distributed queue server"

Gem::Specification.new do |s|
  s.name = GEM
  s.version = VER
  s.authors = AUTHORS
  s.email = EMAILS
  s.homepage = HOMEPAGE
  s.summary = SUMMARY
  s.description = s.summary

  s.require_path = 'lib'
  s.executables = ["starling"]

  # get this easily and accurately by running 'Dir.glob("{lib,test}/**/*")'
  # in an IRB session.  However, GitHub won't allow that command hence
  # we spell it out.
  s.files = ["README.rdoc", "LICENSE", "CHANGELOG", "Rakefile", "lib/starling", "lib/starling/handler.rb", "lib/starling/persistent_queue.rb", "lib/starling/queue_collection.rb", "lib/starling/runner.rb", "lib/starling/server.rb", "lib/starling.rb", "test/test_helper.rb", "test/test_persistent_queue.rb", "test/test_starling.rb"]
  s.test_files = ["test/test_helper.rb", "test/test_persistent_queue.rb", "test/test_starling.rb"]

  s.has_rdoc = true
  s.rdoc_options = ["--quiet", "--title", "starling documentation", "--opname", "index.html", "--line-numbers", "--main", "README.rdoc", "--inline-source"]
  s.extra_rdoc_files = ["README.rdoc", "CHANGELOG", "LICENSE"]

  s.add_dependency 'memcache-client'
end

