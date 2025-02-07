# frozen_string_literal: true

require_relative 'lib/firecrawl/version'

Gem::Specification.new do |spec|
  spec.name          = "firecrawl"
  spec.version       = Firecrawl::VERSION
  spec.authors       = ["Firecrawl, bl4rr0w"]
  spec.email         = [""]

  spec.summary       = %q{Ruby gem for the Firecrawl API}
  spec.description   = %q{This gem provides a Ruby interface for interacting with the Firecrawl API.}
  spec.homepage      = "https://github.com/firecrawl/firecrawl"
  spec.license       = "AGPL-3.0"

  spec.files         = Dir.glob('lib/**/*') + %w(README.md LICENSE.txt)
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "httparty"
  spec.add_dependency "websocket-client-simple"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
