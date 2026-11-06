# frozen_string_literal: true

require_relative "lib/cookiejar_consent/version"

Gem::Specification.new do |spec|
  spec.name = "cookiejar-consent"
  spec.version = CookiejarConsent::VERSION
  spec.authors = ["Alaa Sarhan"]
  spec.summary = "Cookie consent banner with Google Consent Mode v2, built from cookiejar scan reports"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "assets/**/*", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["cookiejar-consent"]
  spec.require_paths = ["lib"]

  spec.add_dependency "csv", "~> 3.3"
  spec.add_dependency "json", ">= 2.7" # script_safe
end
