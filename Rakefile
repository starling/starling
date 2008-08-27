require 'rubygems'
require 'rake/rdoctask'
require 'spec/rake/spectask'

task :default => :spec

task :install do
  sh %{gem build starling.gemspec}
  sh %{sudo gem install starling-*.gem}
end

Spec::Rake::SpecTask.new do |t|
  t.ruby_opts = ['-rtest/unit']
  t.spec_files = FileList['spec/*_spec.rb']
  t.fail_on_error = true
end
  
Rake::RDocTask.new do |rd|
  rd.main = "README.rdoc"
  rd.rdoc_files.include("README.rdoc", "lib/**/*.rb")
  rd.rdoc_dir = 'doc'
end
