# frozen_string_literal: true

require "csv"
require "fileutils"

module Cookiejar
  # Writes all discovered cookies to one CSV file, named after the time of the
  # scan so consecutive scans into the same directory don't overwrite each other
  # and sort chronologically by name.
  class Report
    HEADERS = ["cookie name", "category", "cookie purpose/description", "storage duration", "security settings",
               "full details"].freeze
    FILE_PREFIX = "cookies-"
    FILE_PATTERN = "#{FILE_PREFIX}*.csv".freeze
    TIMESTAMP_FORMAT = "%Y%m%d-%H%M%S"

    def initialize(output_dir:, include_values: false, time: Time.now)
      @output_dir = output_dir
      @include_values = include_values
      @time = time
    end

    # Report files in a directory, oldest first.
    def self.files_in(dir)
      Dir.glob(File.join(dir, FILE_PATTERN)).sort
    end

    # @param cookies [Array<CookieRecord>] classified cookies
    # @return [String] path of the written file
    def write(cookies)
      FileUtils.mkdir_p(@output_dir)
      path = unused_path
      rows = cookies.sort_by do |c|
        [CATEGORIES.index(c.classification.category), c.name.downcase, c.domain, c.path.to_s]
      end
      CSV.open(path, "w", write_headers: true, headers: HEADERS) do |csv|
        rows.each { |cookie| csv << row_for(cookie) }
      end
      path
    end

    private

    def unused_path
      base = File.join(@output_dir, "#{FILE_PREFIX}#{@time.strftime(TIMESTAMP_FORMAT)}")
      path = "#{base}.csv"
      suffix = 1
      # "_" sorts after ".", keeping files of scans within the same second in order.
      path = "#{base}_#{suffix += 1}.csv" while File.exist?(path)
      path
    end

    def row_for(cookie)
      [
        cookie.name,
        cookie.classification.category,
        cookie.classification.description.to_s,
        cookie.storage_duration,
        cookie.security_settings,
        cookie.details_json(include_value: @include_values)
      ]
    end
  end
end
