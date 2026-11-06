# frozen_string_literal: true

module Cookiejar
  # Runs a full scan: crawl, classify, write the report.
  class Scanner
    Result = Struct.new(:pages, :cookies, :file, keyword_init: true)

    def initialize(config, logger: nil, browser: nil)
      @config = config.validate!
      @logger = logger
      @browser = browser
    end

    def run
      database = cookie_database
      browser = @browser || Browser.new(
        page_timeout: @config.page_timeout,
        settle_time: @config.settle_time,
        max_settle_time: @config.max_settle_time,
        browser_path: @config.browser_path,
        headless: @config.headless,
        consent: consent,
        logger: @logger
      )
      crawler = Crawler.new(
        browser: browser,
        link_filter: LinkFilter.from_config(@config),
        follow_links: @config.follow_links,
        depth: @config.depth,
        max_pages: @config.max_pages,
        logger: @logger
      ).crawl(@config.start_uris)

      classifier = Classifier.new(threshold: @config.confidence_threshold, custom_rules_file: @config.rules_file,
                                  cookie_database: database)
      cookies = crawler.cookies.values
      cookies.each { |cookie| cookie.classification = classifier.classify(cookie) }

      file = Report.new(output_dir: @config.output_dir, include_values: @config.include_values).write(cookies)
      Result.new(pages: crawler.pages, cookies: cookies, file: file)
    ensure
      browser&.close unless @browser
    end

    private

    # The Open Cookie Database is optional: without it, cookies are classified by the built-in rules only.
    def cookie_database
      path = @config.cookie_database || ENV.fetch("COOKIE_DATABASE", nil)
      problem =
        if path.nil? then "no Open Cookie Database given (--cookie-database or COOKIE_DATABASE)"
        elsif !File.file?(path) then "Open Cookie Database not found at #{path}"
        end
      return CookieDatabase.new(path) unless problem

      @logger&.call("Warning: #{problem}; classifying with the built-in rules only")
      nil
    end

    def consent
      return nil unless @config.accept_consent

      AutoConsent.new(selectors: @config.consent_selectors, wait: @config.consent_wait, logger: @logger)
    end
  end
end
