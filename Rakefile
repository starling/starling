require 'rubygems'
require 'rake/gempackagetask'
require 'rake/rdoctask'
require 'spec/rake/spectask'
require 'starling.gemspec.rb'

spec = gemspec

Rake::GemPackageTask.new(spec) do |pkg|
  pkg.gem_spec = spec
end

task :install => [:package] do
  sh %{sudo gem install pkg/#{GEM}-#{VERSION}}
end

Spec::Rake::SpecTask.new do |t|
  t.ruby_opts = ['-rtest/unit']
  t.spec_files = FileList['test/test_*.rb']
  t.fail_on_error = true
end
  
Rake::RDocTask.new do |rd|
  rd.main = "README.rdoc"
  rd.rdoc_files.include("README.rdoc", "lib/**/*.rb")
  rd.rdoc_dir = 'doc'
  rd.options = spec.rdoc_options
end