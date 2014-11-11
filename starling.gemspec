# coding: utf-8

Gem::Specification.new do |spec|
  spec.name          = "starling"
  spec.version       = "0.10.1"
  spec.authors       = ["Blaine Cook", "Chris Wanstrath", "Britt Selvitelle", "Glenn Rempe", "Abdul-Rahman Advany", "Seth Fitzsimmons", "Harm Aarts", "Chris Gaffney"]
  spec.description   = %q{Starling is a light-weight, persistent queue server that speaks the memcached protocol. It was originally developed for Twitter's backend.}
  spec.summary       = %q{Starling is a lightweight, transactional, distributed queue server}
  spec.homepage      = %q{http://github.com/starling/starling/}

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.rdoc_options = ["--quiet", "--title", "starling documentation", "--opname", "index.html", "--line-numbers", "--main", "README.rdoc", "--inline-source"]
  spec.add_dependency "memcache-client", '~> 1.7.0'
  spec.add_dependency "eventmachine", "~> 1.0.3"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3"
end
