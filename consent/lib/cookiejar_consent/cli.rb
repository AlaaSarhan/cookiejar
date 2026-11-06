# frozen_string_literal: true

require "optparse"

module CookiejarConsent
  # cookiejar-consent [options] [REPORT]
  class CLI
    DEFAULT_REPORTS_DIR = "cookie-report"

    def self.start(argv, out: $stdout, err: $stderr)
      new(out: out, err: err).run(argv)
    end

    def initialize(out:, err:)
      @out = out
      @err = err
    end

    # @return [Integer] process exit status
    def run(argv)
      dir = DEFAULT_REPORTS_DIR
      file = nil
      format = nil
      unknown = "unknown"
      options = {}
      parser = OptionParser.new do |o|
        o.banner = "Usage: cookiejar-consent [options] [REPORT]"
        o.separator ""
        o.separator "Writes the cookie consent banner script with the cookies of a cookiejar report"
        o.separator "built in, or the cookie list as JSON for the banner to load. Without a report"
        o.separator "file, uses the newest report in the reports directory."
        o.separator ""
        o.on("-r", "--reports DIR", "Directory with reports (default: #{dir})") { |v| dir = v }
        o.on("-w", "--write FILE", "Write to FILE instead of stdout") { |v| file = v }
        o.on("--format FORMAT", Builder::FORMATS, "js (banner script) or json (cookie list) " \
                                                  "(default: from --write extension, else js)") { |v| format = v }
        o.on("--options FILE", "YAML or JSON file with banner options to build in") do |v|
          options = Builder.load_options(v)
        end
        o.on("--unknown CATEGORY", Builder::UNKNOWN_OPTIONS,
             "Category for unclassified cookies: unknown (own category), performance or marketing " \
             "(default: unknown)") { |v| unknown = v }
        o.on("-v", "--version", "Print version") do
          @out.puts(VERSION)
          return 0
        end
        o.on("-h", "--help", "Print this help") do
          @out.puts(o)
          return 0
        end
      end
      paths = parser.parse(argv)
      raise Error, "takes one report file, or none to use the newest" if paths.size > 1

      report = paths.first || CookiejarConsent.reports_in(dir).last || raise(Error, "no reports in #{dir}")
      format ||= file&.end_with?(".json") ? "json" : "js"
      output = Builder.new(report, unknown: unknown, options: options).render(format)
      if file
        File.write(file, output)
        @err.puts("Banner #{format == "js" ? "script" : "cookie list"} for #{report}: #{file}")
      else
        @out.puts(output)
      end
      0
    rescue Error, OptionParser::ParseError, SystemCallError => e
      @err.puts("cookiejar-consent: #{e.message}")
      @err.puts("Run 'cookiejar-consent --help' for usage.")
      2
    end
  end
end
