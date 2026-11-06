# frozen_string_literal: true

require "optparse"

module Cookiejar
  class CLI
    def self.start(argv, out: $stdout, err: $stderr)
      new(out: out, err: err).run(argv)
    end

    def initialize(out:, err:)
      @out = out
      @err = err
    end

    # @return [Integer] process exit status
    def run(argv)
      return diff(argv.drop(1)) if argv.first == "diff"

      config = parse(argv)
      return 0 if config.nil?

      result = Scanner.new(config, logger: ->(msg) { @err.puts(msg) }).run
      print_summary(result)
      0
    rescue Error, OptionParser::ParseError => e
      @err.puts("cookiejar: #{e.message}")
      @err.puts("Run 'cookiejar --help' for usage.")
      2
    end

    def parse(argv)
      cli = {}
      config_file = nil
      parser = build_parser(cli, ->(path) { config_file = path })
      start_uris = parser.parse(argv)
      return nil if cli.delete(:exit)

      config = Config.new
      config.apply(Config.load_yaml(config_file)) if config_file
      config.apply(cli)
      config.apply(start_uris: start_uris)
      config
    end

    # cookiejar diff [-o DIR] [OLD NEW]
    def diff(argv)
      dir = Config::DEFAULTS[:output_dir]
      parser = OptionParser.new do |o|
        o.banner = "Usage: cookiejar diff [options] [OLD_REPORT NEW_REPORT]"
        o.separator ""
        o.separator "Lists cookies added, modified and removed between two reports."
        o.separator "Without report files, compares the two newest reports in the output directory."
        o.separator ""
        o.on("-o", "--output DIR", "Directory with reports (default: #{dir})") { |v| dir = v }
        o.on("-h", "--help", "Print this help") do
          @out.puts(o)
          return 0
        end
      end
      paths = parser.parse(argv)
      report_diff =
        case paths.size
        when 0 then ReportDiff.latest(dir)
        when 2 then ReportDiff.new(*paths)
        else raise Error, "diff takes two report files, or none to compare the newest two"
        end
      @out.puts(report_diff)
      0
    rescue Error, OptionParser::ParseError => e
      @err.puts("cookiejar diff: #{e.message}")
      @err.puts("Run 'cookiejar diff --help' for usage.")
      2
    end

    private

    def build_parser(cli, on_config)
      list = ->(key) { ->(value) { (cli[key] ||= []).concat(value.split(",").map(&:strip).reject(&:empty?)) } }

      OptionParser.new do |o|
        o.banner = "Usage: cookiejar [options] START_URI [START_URI...]\n" \
                   "       cookiejar diff [options] [OLD_REPORT NEW_REPORT]"
        o.separator ""
        o.separator "Scans websites for cookies and writes a CSV report of all cookies and their"
        o.separator "category (functionality, performance, marketing, unknown), named after the"
        o.separator "time of the scan. 'diff' compares two reports, see 'cookiejar diff --help'."
        o.separator "Build a consent banner from a report with cookiejar-consent."
        o.separator ""
        o.separator "Crawling:"
        o.on("-c", "--config FILE", "YAML config file (CLI options take precedence)") { |v| on_config.call(v) }
        o.on("--[no-]follow-links", "Follow links found on pages (default: on)") { |v| cli[:follow_links] = v }
        o.on("-d", "--depth N", Integer, "Max link depth from a start URI (default: 1)") { |v| cli[:depth] = v }
        o.on("--max-pages N", Integer, "Stop after visiting N pages (default: 100)") { |v| cli[:max_pages] = v }
        o.separator ""
        o.separator "Link filters (repeatable or comma separated; wildcards: * within a path segment, ** across):"
        o.on("--allow-domain DOMAIN", "Follow links to DOMAIN and its subdomains (default: start URI hosts)",
             &list.call(:allowed_domains))
        o.on("--include-href PATTERN", "Only follow links whose href attribute matches", &list.call(:include_hrefs))
        o.on("--exclude-href PATTERN", "Never follow links whose href attribute matches", &list.call(:exclude_hrefs))
        o.on("--include-path PATTERN", "Only follow links whose URL path matches", &list.call(:include_paths))
        o.on("--exclude-path PATTERN", "Never follow links whose URL path matches", &list.call(:exclude_paths))
        o.separator ""
        o.separator "Classification & output:"
        o.on("-o", "--output DIR", "Directory for the CSV report (default: cookie-report)") { |v| cli[:output_dir] = v }
        o.on("--threshold N", Float, "Min confidence to assign a category, exclusive (default: 0.8)") do |v|
          cli[:confidence_threshold] = v
        end
        o.on("--rules FILE", "YAML file with custom rules that override built-in ones") { |v| cli[:rules_file] = v }
        o.on("--cookie-database FILE", "Open Cookie Database CSV (or env COOKIE_DATABASE)") do |v|
          cli[:cookie_database] = v
        end
        o.on("--include-values", "Include cookie values in the full details JSON") { cli[:include_values] = true }
        o.separator ""
        o.separator "Browser:"
        o.on("--browser-path PATH", "Chromium-based browser binary (or env BROWSER_PATH)") { |v| cli[:browser_path] = v }
        o.on("--timeout SECONDS", Integer, "Page load timeout (default: 30)") { |v| cli[:page_timeout] = v }
        o.on("--settle SECONDS", Float, "Wait until no requests or cookie changes for this long (default: 2)") do |v|
          cli[:settle_time] = v
        end
        o.on("--max-settle SECONDS", Float, "Max wait for a page to settle (default: 15)") do |v|
          cli[:max_settle_time] = v
        end
        o.on("--[no-]headless", "Run the browser headless (default: on)") { |v| cli[:headless] = v }
        o.separator ""
        o.separator "Cookie consent:"
        o.on("--[no-]accept-consent", "Accept cookie consent banners to load all cookies (default: on)") do |v|
          cli[:accept_consent] = v
        end
        o.on("--consent-selector SELECTOR", "CSS selector of an accept button, tried first (repeatable)") do |v|
          (cli[:consent_selectors] ||= []) << v
        end
        o.on("--consent-wait SECONDS", Float, "Max wait for a banner per host (default: 5)") do |v|
          cli[:consent_wait] = v
        end
        o.separator ""
        o.on("-v", "--version", "Print version") do
          @out.puts(VERSION)
          cli[:exit] = true
        end
        o.on("-h", "--help", "Print this help") do
          @out.puts(o)
          cli[:exit] = true
        end
      end
    end

    def print_summary(result)
      counts = result.cookies.group_by { |c| c.classification.category }.transform_values(&:size)
      failed = result.pages.count { |p| p[:error] }
      @out.puts("Visited #{result.pages.size} page(s)#{", #{failed} with errors" if failed.positive?}; " \
                "found #{result.cookies.size} unique cookie(s).")
      CATEGORIES.each { |category| @out.puts(format("  %-14s %3d", category, counts.fetch(category, 0))) }
      @out.puts("Report: #{result.file}")
    end
  end
end
