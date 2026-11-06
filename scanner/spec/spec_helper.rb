# frozen_string_literal: true

require "cookiejar"
require "tmpdir"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.filter_run_excluding(:browser) if ENV["SKIP_BROWSER_SPECS"]
end
