# frozen_string_literal: true

require_relative "cookiejar/version"

module Cookiejar
  class Error < StandardError; end

  CATEGORIES = %w[functionality performance marketing unknown].freeze
end

require_relative "cookiejar/glob"
require_relative "cookiejar/config"
require_relative "cookiejar/link_filter"
require_relative "cookiejar/cookie_record"
require_relative "cookiejar/cookie_database"
require_relative "cookiejar/classifier"
require_relative "cookiejar/auto_consent"
require_relative "cookiejar/browser"
require_relative "cookiejar/crawler"
require_relative "cookiejar/report"
require_relative "cookiejar/report_diff"
require_relative "cookiejar/scanner"
require_relative "cookiejar/cli"
