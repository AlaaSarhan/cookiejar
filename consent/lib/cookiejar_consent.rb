# frozen_string_literal: true

require_relative "cookiejar_consent/version"

# Builds the cookiejar consent banner from a cookiejar scanner report.
module CookiejarConsent
  class Error < StandardError; end

  # Consent categories, as the scanner assigns them to cookies.
  CATEGORIES = %w[functionality performance marketing unknown].freeze

  # Columns of a scanner report (see the scanner README, "Output"). The report
  # is the only interface between the scanner and the banner.
  REPORT_HEADERS = ["cookie name", "category", "cookie purpose/description", "storage duration",
                    "security settings", "full details"].freeze
  REPORT_PATTERN = "cookies-*.csv"

  # Report files in a directory, oldest first: names hold the time of the scan.
  def self.reports_in(dir)
    Dir.glob(File.join(dir, REPORT_PATTERN)).sort
  end
end

require_relative "cookiejar_consent/builder"
require_relative "cookiejar_consent/cli"
