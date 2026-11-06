# frozen_string_literal: true

require "uri"

module Cookiejar
  # Breadth-first crawl starting from each start URI, collecting every cookie
  # present in the browser after each page load.
  #
  # Start URIs are depth 0. Links found on a page at depth d are followed
  # (as depth d + 1) only when link following is enabled, d < max depth, and
  # the link passes the {LinkFilter}.
  #
  # Each page is visited at most once. URLs are compared after normalization
  # (fragment dropped, scheme and host lowercased, default port and empty path
  # canonicalized), so duplicate start URIs and links that only differ in those
  # parts are not loaded again. The final URL a request lands on after
  # redirects also counts as visited, so a queued URL that a previous page
  # already redirected to is skipped.
  class Crawler
    attr_reader :cookies, :pages

    def initialize(browser:, link_filter:, follow_links: true, depth: 1, max_pages: 100, logger: nil)
      @browser = browser
      @link_filter = link_filter
      @follow_links = follow_links
      @max_depth = depth.to_i
      @max_pages = max_pages.to_i
      @logger = logger
      @cookies = {}
      @pages = []
    end

    def crawl(start_uris)
      queue = start_uris.uniq { |uri| normalize(uri) }.map { |uri| [uri, 0, uri] }
      seen = Set.new(queue.map { |uri, _, _| normalize(uri) })
      visited = Set.new

      until queue.empty? || @pages.size >= @max_pages
        url, depth, site = queue.shift
        key = normalize(url)
        if visited.include?(key)
          log("    skipping #{url} (already visited)")
          next
        end

        result = @browser.visit(url)
        visited << key
        if result.final_url
          final_key = normalize(result.final_url)
          visited << final_key
          seen << final_key
        end
        @pages << { url: url, final_url: result.final_url, depth: depth, error: result.error, consent: result.consent }
        log("[#{@pages.size}] depth=#{depth} #{url}#{" (#{result.error})" if result.error}")
        log("    accepted cookie consent: #{result.consent}") if result.consent

        record_cookies(result.cookies, page_url: result.final_url || url, site_url: site)
        next unless @follow_links && depth < @max_depth

        result.links.each do |link|
          next unless @link_filter.follow?(href: link[:href], url: link[:url])

          link_key = normalize(link[:url])
          next if seen.include?(link_key)

          seen << link_key
          queue << [link_key, depth + 1, site]
        end
      end

      log("Stopped after reaching max pages (#{@max_pages})") if queue.any? { |url, _, _| !visited.include?(normalize(url)) }
      self
    end

    private

    def record_cookies(raw_cookies, page_url:, site_url:)
      Array(raw_cookies).each do |attrs|
        key = CookieRecord.key_for(attrs)
        if (existing = @cookies[key])
          existing.observe(attrs, page_url: page_url)
        else
          @cookies[key] = CookieRecord.new(attrs, page_url: page_url, site_url: site_url)
        end
      end
    end

    def normalize(url)
      uri = URI.parse(url)
      uri.fragment = nil
      uri.host = uri.host&.downcase
      uri.path = "/" if uri.path.to_s.empty? && uri.is_a?(URI::HTTP)
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def log(message)
      @logger&.call(message)
    end
  end
end
