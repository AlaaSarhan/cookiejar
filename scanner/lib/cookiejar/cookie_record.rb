# frozen_string_literal: true

require "json"
require "time"
require "uri"
require "public_suffix"

module Cookiejar
  # A unique cookie (by name, domain and path) observed during a scan,
  # built from the raw CDP cookie hash (Network.Cookie).
  class CookieRecord
    DURATION_UNITS = [
      ["year", 365 * 86_400],
      ["month", 30 * 86_400],
      ["day", 86_400],
      ["hour", 3_600],
      ["minute", 60],
      ["second", 1]
    ].freeze

    attr_reader :attributes, :first_seen_on, :seen_on, :observed_at
    attr_accessor :classification

    def self.key_for(attributes)
      [attributes["name"], attributes["domain"].to_s.downcase, attributes["path"]]
    end

    def initialize(attributes, page_url:, site_url:, observed_at: Time.now)
      @attributes = attributes
      @first_seen_on = page_url
      @site_url = site_url
      @seen_on = [page_url]
      @observed_at = observed_at
    end

    def key = self.class.key_for(attributes)
    def name = attributes["name"]
    def domain = attributes["domain"].to_s.downcase.delete_prefix(".")
    def path = attributes["path"]
    def session? = attributes["session"] || attributes["expires"].to_f <= 0

    def observe(attributes, page_url:)
      @attributes = attributes
      @seen_on << page_url unless @seen_on.include?(page_url)
    end

    def expires_at
      return nil if session?

      Time.at(attributes["expires"].to_f).utc
    end

    def lifetime_seconds
      return nil if session?

      (attributes["expires"].to_f - observed_at.to_f).round
    end

    def first_party?
      site = registrable_domain(URI.parse(@site_url).host)
      site && site == registrable_domain(domain)
    rescue URI::InvalidURIError
      false
    end

    def storage_duration
      seconds = lifetime_seconds
      return "Session" if seconds.nil?
      return "Expired" unless seconds.positive?

      # Lifetimes are measured from when the scan saw the cookie, a few seconds
      # after it was set; round to the smallest unit shown so 90 days don't
      # turn into "2 months 29 days".
      # Rounding can carry into a larger unit (12 months 5 days -> 1 year).
      seconds = round_to_shown_precision(round_to_shown_precision(seconds))
      remaining = seconds
      DURATION_UNITS[largest_unit_index(seconds), 2].filter_map do |unit, size|
        count, remaining = remaining.divmod(size)
        "#{count} #{unit}#{"s" unless count == 1}" if count.positive?
      end.join(" ")
    end

    def security_settings
      flags = []
      flags << "Secure" if attributes["secure"]
      flags << "HttpOnly" if attributes["httpOnly"]
      flags << "SameSite=#{attributes["sameSite"] || "Unset"}"
      flags << "Partitioned" if attributes["partitionKey"]
      flags.join("; ")
    end

    def details(include_value: false)
      raw = include_value ? attributes : attributes.except("value")
      raw.merge(
        "expiresAt" => expires_at&.iso8601,
        "storageDuration" => storage_duration,
        "party" => first_party? ? "first" : "third",
        "firstSeenOn" => first_seen_on,
        "seenOn" => seen_on,
        "classification" => classification&.to_h
      )
    end

    def details_json(include_value: false)
      JSON.generate(details(include_value: include_value))
    end

    private

    def largest_unit_index(seconds)
      DURATION_UNITS.index { |_, size| seconds >= size } || (DURATION_UNITS.size - 1)
    end

    # Rounds what is left below the largest unit to the second largest unit.
    def round_to_shown_precision(seconds)
      index = largest_unit_index(seconds)
      size = DURATION_UNITS[index].last
      precision = DURATION_UNITS.fetch(index + 1, DURATION_UNITS[index]).last
      count, rest = seconds.divmod(size)
      (count * size) + ((rest.to_f / precision).round * precision)
    end

    def registrable_domain(host)
      return nil if host.nil? || host.empty?

      PublicSuffix.domain(host, ignore_private: true) || host
    rescue PublicSuffix::Error
      host
    end
  end
end
