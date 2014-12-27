# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
require "#{lib}/constants"

Gem::Specification.new do |spec|
  spec.name          = "pomodori"
  spec.version       = Pomodori::VERSION_STRING
  spec.authors       = ["Hongli Lai"]
  spec.email         = ["hongli@phusion.nl"]
  spec.summary       = %q{Simple web app server setup and deployment}
  #spec.description   = %q{TODO: Write a longer description. Optional.}
  spec.homepage      = "http://phusion.github.io/pomodori/"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib/dummy"]

  spec.add_dependency "capistrano", "~> 3.3"
  spec.add_dependency "capistrano-rvm"
  spec.add_dependency "capistrano-bundler"
  spec.add_dependency "capistrano-rails"
  spec.add_dependency "json"
  spec.add_dependency "paint"
  spec.add_dependency "hashie", "~> 3.3"
end
