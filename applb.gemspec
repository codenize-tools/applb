# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'applb/version'

Gem::Specification.new do |spec|
  spec.name          = 'applb'
  spec.version       = Applb::VERSION
  spec.authors       = ['wata']
  spec.email         = ['wata.gm@gmail.com']

  spec.summary       = %q{Codenize ELB v2 (ALB)}
  spec.description   = %q{Manage ALB by DSL}
  spec.homepage      = 'https://github.com/codenize-tools/applb'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_dependency 'aws-sdk-elasticloadbalancingv2', '>= 1.6.0'
  spec.add_dependency 'hashie'
  spec.add_dependency 'diffy'
  spec.add_dependency 'term-ansicolor'

  spec.add_development_dependency 'bundler'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'pry-byebug'
end
