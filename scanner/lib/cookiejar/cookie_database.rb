# frozen_string_literal: true

require "csv"

module Cookiejar
  # Looks cookies up in the Open Cookie Database
  # (https://github.com/jkwakman/Open-Cookie-Database), a community maintained
  # list of cookie names with their platform, category, purpose and retention.
  #
  # Entries match a cookie by exact name, or by name prefix when the entry is
  # marked as a wildcard. The database's domain column names the platform's
  # domain, but many of these cookies are set first-party by the platform's
  # JavaScript (e.g. Facebook's _fbp), so a domain mismatch does not rule out an
  # entry. It only matters for names too generic to identify a platform on
  # their own: those need a matching domain to pass the default threshold.
  # Generic are names of up to three characters (e.g. "IDE", "c", or the prefix
  # "_s"), and plain lowercase words listed for a platform's domain (e.g.
  # "sessionid" for Instagram or "locale" for Facebook).
  class CookieDatabase
    CATEGORIES = {
      "Functional" => "functionality",
      "Necessary" => "functionality",
      "Security" => "functionality",
      "Personalization" => "functionality",
      "Analytics" => "performance",
      "Marketing" => "marketing"
    }.freeze

    SHORT_NAME_LENGTH = 3

    CONFIDENCE = {
      domain_match: 0.95,
      name: 0.9,
      prefix: 0.85,
      generic: 0.6
    }.freeze

    Entry = Struct.new(:id, :platform, :category, :name, :domains, :description, :retention_period,
                       :data_controller, :privacy_portal, :wildcard, keyword_init: true) do
      def generic? = name.length <= SHORT_NAME_LENGTH || (domains.any? && name.match?(/\A[a-z]+\z/))

      def matches_name?(cookie_name) = wildcard ? cookie_name.start_with?(name) : cookie_name == name

      def matches_domain?(cookie_domain)
        domains.any? { |d| cookie_domain == d || cookie_domain.end_with?(".#{d}") }
      end

      # How the entry is shown in a cookie's report details.
      def to_h
        {
          "id" => id, "platform" => platform, "category" => category, "name" => name,
          "wildcardMatch" => wildcard, "description" => description, "retentionPeriod" => retention_period,
          "dataController" => data_controller, "privacyPortal" => privacy_portal
        }.compact
      end
    end

    Match = Struct.new(:entry, :category, :confidence, keyword_init: true)

    def initialize(path)
      @exact = {}
      @prefixes = []
      CSV.foreach(path, headers: true) do |row|
        entry = build_entry(row)
        next unless entry

        entry.wildcard ? @prefixes << entry : (@exact[entry.name] ||= []) << entry
      end
    rescue Errno::ENOENT
      raise Error, "cookie database not found: #{path}"
    end

    def size = @exact.values.sum(&:size) + @prefixes.size

    # @param cookie [CookieRecord]
    # @return [Match, nil] the most specific, most confident matching entry
    def lookup(cookie)
      candidates = @exact.fetch(cookie.name, []).map { |e| match_for(e, cookie, exact: true) } +
                   @prefixes.select { |e| e.matches_name?(cookie.name) }
                            .map { |e| match_for(e, cookie, exact: false) }
      # Prefer exact names, then longer prefixes, then confidence.
      candidates.max_by { |m| [m.entry.wildcard ? 0 : 1, m.entry.name.length, m.confidence] }
    end

    private

    def match_for(entry, cookie, exact:)
      confidence =
        if entry.matches_domain?(cookie.domain) then CONFIDENCE[:domain_match]
        elsif entry.generic? then CONFIDENCE[:generic]
        elsif exact then CONFIDENCE[:name]
        else CONFIDENCE[:prefix]
        end
      Match.new(entry: entry, category: CATEGORIES.fetch(entry.category), confidence: confidence)
    end

    def build_entry(row)
      name = row["Cookie / Data Key name"].to_s.strip
      return nil if name.empty? || !CATEGORIES.key?(row["Category"])

      Entry.new(
        id: row["ID"],
        platform: presence(row["Platform"]),
        category: row["Category"],
        name: name,
        domains: parse_domains(row["Domain"]),
        description: presence(row["Description"]),
        retention_period: presence(row["Retention period"]),
        data_controller: presence(row["Data Controller"]),
        privacy_portal: presence(row["User Privacy & GDPR Rights Portals"]),
        wildcard: row["Wildcard match"] == "1"
      )
    end

    # "doubleclick.net (3rd party)", ".bing.com (3rd party) or .microsoft.com (3rd party)"
    def parse_domains(value)
      value.to_s.split(/\s+or\s+|,/).filter_map do |part|
        domain = part.sub(/\(.*?\)/, "").strip.downcase.delete_prefix(".")
        domain unless domain.empty?
      end
    end

    def presence(value)
      value = value.to_s.strip
      value.empty? ? nil : value
    end
  end
end
