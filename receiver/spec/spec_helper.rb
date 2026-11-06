# frozen_string_literal: true

require "consent_log"
require "rack/test"
require "tmpdir"
require "logger"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.include Rack::Test::Methods
end
