# frozen_string_literal: true

require_relative "lib/cookiejar/version"

Gem::Specification.new do |spec|
  spec.name = "cookiejar"
  spec.version = Cookiejar::VERSION
  spec.authors = ["Alaa Sarhan"]
  spec.summary = "Scans websites for cookies and produces categorised CSV reports for cookie consent configuration"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "data/**/*", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["cookiejar"]
  spec.require_paths = ["lib"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "ferrum", "~> 0.17"
  spec.add_dependency "public_suffix", ">= 5.0"
end
