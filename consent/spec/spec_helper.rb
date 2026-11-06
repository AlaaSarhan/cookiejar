# frozen_string_literal: true

require "cookiejar_consent"
require "fileutils"
require "tmpdir"

module ReportHelpers
  FIXTURES = File.expand_path("fixtures", __dir__)

  # A report written by the cookiejar scanner: PHPSESSID (functionality), _ga
  # (performance, twice), _fbp and IDE (marketing) and mystery_x (unknown).
  def fixture_report = File.join(FIXTURES, "cookies-20231114-221320.csv")

  # Copies the fixture report into dir under the name of a later scan.
  def copy_report(dir, name: File.basename(fixture_report))
    FileUtils.cp(fixture_report, File.join(dir, name))
    File.join(dir, name)
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.order = :random
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.include ReportHelpers
  config.filter_run_excluding(:browser) if ENV["SKIP_BROWSER_SPECS"]
end
