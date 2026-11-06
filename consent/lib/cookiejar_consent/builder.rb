# frozen_string_literal: true

require "csv"
require "digest"
require "json"
require "time"
require "yaml"

module CookiejarConsent
  # Turns a cookiejar scanner report into the cookie list of the consent banner
  # in assets/cookiejar-consent.js, either as JSON for the banner to load or as
  # the banner script with the cookies built in.
  class Builder
    SCRIPT = File.expand_path("../../assets/cookiejar-consent.js", __dir__)
    PLACEHOLDER = "/*COOKIEJAR_CONFIG*/ null"
    FORMATS = %w[js json].freeze
    # What to do with cookies the scanner could not classify.
    UNKNOWN_OPTIONS = %w[unknown performance marketing].freeze

    attr_reader :report_path

    # @param report_path [String] CSV report
    # @param unknown [String] category to list unclassified cookies in; "unknown"
    #   keeps them in their own category, which also needs consent
    # @param options [Hash] banner options embedded in the script, see the README
    def initialize(report_path, unknown: "unknown", options: {})
      raise Error, "invalid category for unknown cookies: #{unknown}" unless UNKNOWN_OPTIONS.include?(unknown)

      @report_path = report_path
      @unknown = unknown
      @options = options
    end

    def self.load_options(path)
      data = YAML.safe_load_file(path) || {}
      raise Error, "banner options in #{path} must be a mapping" unless data.is_a?(Hash)

      data
    rescue Errno::ENOENT
      raise Error, "banner options file not found: #{path}"
    rescue Psych::SyntaxError => e
      raise Error, "cannot read banner options #{path}: #{e.message}"
    end

    # @return [Hash{String => Array<Hash>}] cookies by category
    def cookies
      @cookies ||= begin
        grouped = CATEGORIES.to_h { |category| [category, {}] }
        rows.each do |row|
          entry = entry_for(row)
          category = row["category"] == "unknown" ? @unknown : row["category"]
          next unless grouped.key?(category)

          # The banner lists a cookie once per domain, whatever paths it was set on.
          grouped[category][[entry["name"], entry["domain"]]] ||= entry
        end
        grouped.transform_values { |entries| entries.values.sort_by { |e| [e["name"].downcase, e["domain"]] } }
      end
    end

    # The banner's options and cookies, and where they came from. The fingerprint
    # identifies what visitors were shown; consent records carry it, so keep the
    # banner files of each fingerprint to prove what a visitor agreed to.
    def config
      content = @options.merge("cookies" => cookies)
      content.merge(
        "source" => {
          "report" => File.basename(@report_path),
          "fingerprint" => Digest::SHA256.hexdigest(JSON.generate(content))[0, 16],
          "generated" => Time.now.utc.iso8601
        }
      )
    end

    def to_json(*_args) = JSON.pretty_generate(config)

    # The banner script with the config built in.
    def to_js
      script = File.read(SCRIPT)
      raise Error, "#{SCRIPT} has no config placeholder" unless script.include?(PLACEHOLDER)

      # script_safe escapes "</script>" and line separators, so the result can also be inlined in HTML;
      # ascii_only keeps it readable on pages that load it without a charset.
      script.sub(PLACEHOLDER) { JSON.generate(config, script_safe: true, ascii_only: true) }
    end

    def render(format)
      raise Error, "invalid format: #{format} (use #{FORMATS.join(" or ")})" unless FORMATS.include?(format)

      format == "js" ? to_js : to_json
    end

    private

    def rows
      table = CSV.read(@report_path, headers: true)
      missing = REPORT_HEADERS - table.headers
      raise Error, "#{@report_path} is not a cookie report (missing columns: #{missing.join(", ")})" if missing.any?

      table
    rescue Errno::ENOENT
      raise Error, "report not found: #{@report_path}"
    rescue CSV::MalformedCSVError => e
      raise Error, "cannot read report #{@report_path}: #{e.message}"
    end

    def entry_for(row)
      details = JSON.parse(row["full details"].to_s)
      classification = details["classification"] || {}
      {
        "name" => row["cookie name"],
        "domain" => details["domain"].to_s.downcase.delete_prefix("."),
        "path" => details["path"],
        "party" => details["party"],
        "provider" => classification["provider"],
        "description" => row["cookie purpose/description"].to_s.empty? ? nil : row["cookie purpose/description"],
        "duration" => row["storage duration"]
      }.compact
    rescue JSON::ParserError => e
      raise Error, "cannot read report #{@report_path}: #{e.message}"
    end
  end
end
