# frozen_string_literal: true

require "uri"

module Cookiejar
  # Decides whether a discovered link should be followed.
  #
  # A link is followed when all of the following hold:
  # * it resolves to an http(s) URL
  # * its host is one of the allowed domains (or a subdomain of one)
  # * its raw href attribute matches an include_hrefs pattern (if any are given)
  #   and none of the exclude_hrefs patterns
  # * its URL path matches an include_paths pattern (if any are given)
  #   and none of the exclude_paths patterns
  #
  # All href/path patterns support wildcards, see {Glob}.
  class LinkFilter
    def initialize(allowed_domains:, include_hrefs: [], exclude_hrefs: [], include_paths: [], exclude_paths: [])
      @allowed_domains = allowed_domains.map { |d| d.downcase.delete_prefix("*.").delete_prefix(".") }
      @include_hrefs = include_hrefs.map { |p| Glob.to_regexp(p) }
      @exclude_hrefs = exclude_hrefs.map { |p| Glob.to_regexp(p) }
      @include_paths = include_paths.map { |p| Glob.to_regexp(p) }
      @exclude_paths = exclude_paths.map { |p| Glob.to_regexp(p) }
    end

    def self.from_config(config)
      new(
        allowed_domains: config.effective_allowed_domains,
        include_hrefs: config.include_hrefs,
        exclude_hrefs: config.exclude_hrefs,
        include_paths: config.include_paths,
        exclude_paths: config.exclude_paths
      )
    end

    # @param href [String] the raw value of the link's href attribute
    # @param url [String] the absolute URL the href resolves to
    def follow?(href:, url:)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP) && uri.host

      allowed_domain?(uri.host.downcase) &&
        passes?(href.to_s, @include_hrefs, @exclude_hrefs) &&
        passes?(uri.path.to_s.empty? ? "/" : uri.path, @include_paths, @exclude_paths)
    rescue URI::InvalidURIError
      false
    end

    private

    def allowed_domain?(host)
      @allowed_domains.any? { |domain| host == domain || host.end_with?(".#{domain}") }
    end

    def passes?(subject, includes, excludes)
      return false if excludes.any? { |re| re.match?(subject) }

      includes.empty? || includes.any? { |re| re.match?(subject) }
    end
  end
end
