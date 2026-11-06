# frozen_string_literal: true

require "yaml"

module Cookiejar
  # Assigns a category to a cookie using a rules knowledge base.
  #
  # Evidence is evaluated in order of specificity:
  # 1. custom cookie-name rules (from --rules), which override everything else
  # 2. built-in cookie-name rules
  # 3. the more confident of
  #    * the Open Cookie Database entry for the cookie name, see {CookieDatabase}
  #    * fallback evidence from the cookie's domain and name keywords, combined
  #      per category as independent signals: 1 - (1 - c1) * (1 - c2) * ...
  #
  # A matching Open Cookie Database entry is attached to the classification as
  # reference information, whichever evidence decided the category.
  #
  # The best candidate is only assigned when its confidence is strictly higher
  # than the threshold; otherwise the cookie is categorised as "unknown" and the
  # candidate is kept as a suggestion in the report details.
  class Classifier
    BUILTIN_RULES = File.expand_path("../../data/cookie_rules.yml", __dir__)
    ASSIGNABLE = (CATEGORIES - ["unknown"]).freeze

    Classification = Struct.new(:category, :confidence, :provider, :description, :source, :suggested_category,
                                :open_cookie_database, keyword_init: true) do
      def to_h = super.compact.transform_keys { |k| k.to_s.gsub(/_(\w)/) { ::Regexp.last_match(1).upcase } }
    end

    Rule = Struct.new(:matcher, :category, :confidence, :provider, :description, :domains, :source, keyword_init: true)

    # @param cookie_database [CookieDatabase, nil] nil to classify without it
    def initialize(threshold: 0.8, custom_rules_file: nil, cookie_database: nil)
      @threshold = threshold.to_f
      @cookie_database = cookie_database
      builtin = load_rules(BUILTIN_RULES, "builtin")
      custom = custom_rules_file ? load_rules(custom_rules_file, "custom") : empty_rules
      @custom_cookie_rules = custom[:cookies]
      @cookie_rules = builtin[:cookies]
      @domain_rules = custom[:domains] + builtin[:domains]
      @keyword_rules = custom[:keywords] + builtin[:keywords]
    end

    # @param cookie [CookieRecord]
    # @return [Classification]
    def classify(cookie)
      database_match = @cookie_database&.lookup(cookie)
      candidate = best_name_match(@custom_cookie_rules, cookie) ||
                  best_name_match(@cookie_rules, cookie) ||
                  [database_candidate(database_match), fallback_candidate(cookie)].compact.max_by(&:confidence)
      return Classification.new(category: "unknown", confidence: 0.0) unless candidate

      candidate.open_cookie_database = database_match&.entry&.to_h
      if candidate.confidence <= @threshold
        candidate.suggested_category = candidate.category
        candidate.category = "unknown"
      end
      candidate
    end

    private

    def best_name_match(rules, cookie)
      rule = rules.select { |r| r.matcher.match?(cookie.name) && domain_matches?(r.domains, cookie.domain) }
                  .max_by(&:confidence)
      rule && classification_from(rule, rule.confidence)
    end

    def database_candidate(match)
      return nil unless match

      Classification.new(category: match.category, confidence: match.confidence, provider: match.entry.platform,
                         description: match.entry.description || generic_description(match.category),
                         source: "open-cookie-database")
    end

    def fallback_candidate(cookie)
      signals = @domain_rules.select { |r| domain_matches?(r.domains, cookie.domain) } +
                @keyword_rules.select { |r| r.matcher.match?(cookie.name) }
      return nil if signals.empty?

      category, group = signals.group_by(&:category).max_by { |_, rules| combine(rules.map(&:confidence)) }
      strongest = group.max_by(&:confidence)
      classification_from(
        Rule.new(**strongest.to_h.merge(
          provider: group.filter_map(&:provider).first,
          description: group.filter_map(&:description).first || generic_description(category),
          source: group.map(&:source).uniq.join("+")
        )),
        combine(group.map(&:confidence))
      )
    end

    def combine(confidences)
      (1 - confidences.reduce(1.0) { |acc, c| acc * (1 - c) }).round(4)
    end

    def classification_from(rule, confidence)
      Classification.new(
        category: rule.category,
        confidence: confidence,
        provider: rule.provider,
        description: rule.description || generic_description(rule.category),
        source: rule.source
      )
    end

    def generic_description(category)
      {
        "functionality" => "Required for the website to work as intended.",
        "performance" => "Used to measure website performance, report errors or run experiments.",
        "marketing" => "Used by advertising or marketing platforms."
      }[category]
    end

    def domain_matches?(domains, cookie_domain)
      return true if domains.nil? || domains.empty?

      domains.any? { |d| cookie_domain == d || cookie_domain.end_with?(".#{d}") }
    end

    def empty_rules = { cookies: [], domains: [], keywords: [] }

    def load_rules(path, origin)
      data = YAML.safe_load_file(path) || {}
      {
        cookies: Array(data["cookies"]).map do |r|
          build_rule(r, "#{origin}:name",
                     matcher: Glob.to_regexp(fetch!(r, "name", path)),
                     domains: Array(r["domains"]).map(&:downcase))
        end,
        domains: Array(data["domains"]).map do |r|
          build_rule(r, "#{origin}:domain", matcher: nil, domains: [fetch!(r, "domain", path).downcase])
        end,
        keywords: Array(data["keywords"]).map do |r|
          build_rule(r, "#{origin}:keyword",
                     matcher: Regexp.new(fetch!(r, "pattern", path), Regexp::IGNORECASE),
                     domains: nil)
        end
      }
    rescue Errno::ENOENT
      raise Error, "rules file not found: #{path}"
    end

    def build_rule(raw, source, matcher:, domains:)
      category = raw["category"].to_s.downcase
      raise Error, "invalid category #{raw["category"].inspect} in rule #{raw.inspect}" unless ASSIGNABLE.include?(category)

      Rule.new(matcher: matcher, category: category, confidence: Float(raw.fetch("confidence", 0.9)),
               provider: raw["provider"], description: raw["description"], domains: domains, source: source)
    end

    def fetch!(raw, key, path)
      raw[key] or raise Error, "rule in #{path} is missing '#{key}': #{raw.inspect}"
    end
  end
end
