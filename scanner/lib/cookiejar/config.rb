# frozen_string_literal: true

require "yaml"
require "uri"

module Cookiejar
  # All scan settings. Built from defaults, an optional YAML file and CLI flags
  # (later sources win; list values from CLI flags are appended).
  class Config
    DEFAULTS = {
      start_uris: [],
      follow_links: true,
      depth: 1,
      max_pages: 100,
      allowed_domains: [],
      include_hrefs: [],
      exclude_hrefs: [],
      include_paths: [],
      exclude_paths: [],
      output_dir: "cookie-report",
      confidence_threshold: 0.8,
      include_values: false,
      page_timeout: 30,
      settle_time: 2.0,
      max_settle_time: 15.0,
      browser_path: nil,
      accept_consent: true,
      consent_selectors: [],
      consent_wait: 5.0,
      headless: true,
      rules_file: nil,
      cookie_database: nil
    }.freeze

    LIST_KEYS = %i[start_uris allowed_domains include_hrefs exclude_hrefs include_paths exclude_paths
                   consent_selectors].freeze

    attr_accessor(*DEFAULTS.keys)

    def self.load_yaml(path)
      data = YAML.safe_load_file(path) || {}
      raise Error, "config file #{path} must contain a mapping" unless data.is_a?(Hash)

      data.transform_keys(&:to_sym)
    end

    def initialize(**overrides)
      DEFAULTS.each { |key, value| public_send("#{key}=", value.dup) }
      apply(overrides)
    end

    def apply(values)
      values.each do |key, value|
        key = key.to_sym
        raise Error, "unknown config option: #{key}" unless DEFAULTS.key?(key)

        if LIST_KEYS.include?(key)
          public_send("#{key}=", public_send(key) + Array(value).map(&:to_s))
        else
          public_send("#{key}=", value)
        end
      end
      self
    end

    # Domains links may point to. Defaults to the hosts of the start URIs.
    def effective_allowed_domains
      return allowed_domains unless allowed_domains.empty?

      start_uris.filter_map { |uri| URI.parse(uri).host&.downcase }.uniq
    end

    def validate!
      raise Error, "at least one start URI is required" if start_uris.empty?

      start_uris.each do |uri|
        parsed = URI.parse(uri)
        raise Error, "start URI must be http(s): #{uri}" unless parsed.is_a?(URI::HTTP) && parsed.host
      rescue URI::InvalidURIError
        raise Error, "invalid start URI: #{uri}"
      end
      raise Error, "depth must be >= 0" if depth.to_i.negative?
      raise Error, "max_pages must be >= 1" if max_pages.to_i < 1
      raise Error, "consent_wait must be >= 0" if consent_wait.to_f.negative?
      raise Error, "settle_time must be >= 0" if settle_time.to_f.negative?
      raise Error, "max_settle_time must be >= settle_time" if max_settle_time.to_f < settle_time.to_f
      unless confidence_threshold.to_f.between?(0, 1)
        raise Error, "confidence_threshold must be between 0 and 1"
      end

      self
    end
  end
end
