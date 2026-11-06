# frozen_string_literal: true

require "ferrum"

module Cookiejar
  # Drives a headless Chromium-based browser over CDP. A real browser is needed
  # so cookies set by JavaScript and by third-party resources are captured,
  # not only those sent via Set-Cookie on the HTML document.
  class Browser
    PageResult = Struct.new(:url, :final_url, :cookies, :links, :error, :consent, keyword_init: true)

    # Written by script/install-chromium: path of the installed Chromium.
    INSTALLED_BROWSER_FILE = File.expand_path("../../vendor/chromium/browser-path", __dir__)

    # Chromium-based browsers Ferrum does not look for on its own.
    FALLBACK_BINARIES = [
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
      "/usr/bin/chromium",
      "/usr/bin/chromium-browser",
      "/usr/bin/microsoft-edge",
      "/usr/bin/brave-browser"
    ].freeze

    LINKS_JS = <<~JS
      Array.from(document.querySelectorAll('a[href]')).map(a => [a.getAttribute('href'), a.href])
    JS

    SETTLE_POLL_INTERVAL = 0.1

    # @param settle_time [Numeric] a page counts as settled once no network
    #   request started or finished and no cookie changed for this many seconds
    # @param max_settle_time [Numeric] upper bound for waiting on a page to
    #   settle, for pages that never stop polling or tracking
    # @param consent [AutoConsent, nil] accepts cookie consent banners when given
    def initialize(page_timeout: 30, settle_time: 2.0, max_settle_time: 15.0, browser_path: nil, headless: true,
                   consent: nil, logger: nil)
      @settle_time = settle_time.to_f
      @max_settle_time = max_settle_time.to_f
      @consent = consent
      @logger = logger
      options = { headless: headless, timeout: page_timeout, process_timeout: 30 }
      path = browser_path || ENV.fetch("BROWSER_PATH", nil) || installed_browser
      options[:browser_path] = path if path
      @ferrum = start(options)
    end

    def visit(url)
      error = load { @ferrum.go_to(url) }
      cookies = all_cookies
      if (consent = @consent&.accept(@ferrum))
        # Let the consent platform store the consent and consent-triggered tags
        # run, then reload so tags that only fire on page load with consent run
        # as well. Cookies seen before the reload are kept, in case it replaced
        # or removed them.
        settle
        cookies += all_cookies
        error = load { @ferrum.refresh }
        cookies += all_cookies
      end

      PageResult.new(url: url, final_url: @ferrum.current_url, cookies: cookies, links: collect_links, error: error,
                     consent: consent)
    rescue Ferrum::StatusError, Ferrum::TimeoutError, Ferrum::BrowserError => e
      PageResult.new(url: url, final_url: url, cookies: safe_cookies, links: [], error: e.message)
    end

    def close
      @ferrum&.quit
    end

    private

    def start(options)
      Ferrum::Browser.new(**options)
    rescue Ferrum::BinaryNotFoundError
      raise if options[:browser_path]

      fallback = FALLBACK_BINARIES.find { |p| File.executable?(p) }
      raise Error, "no Chromium-based browser found; run `script/install-chromium` or pass --browser-path" unless fallback

      warn_about(fallback)
      Ferrum::Browser.new(**options, browser_path: fallback)
    end

    # The Chromium installed by `script/install-chromium`, preferred over system browsers.
    def installed_browser
      return nil unless File.file?(INSTALLED_BROWSER_FILE)

      path = File.read(INSTALLED_BROWSER_FILE).strip
      if File.executable?(path)
        @logger&.call("Using browser at #{path}")
        path
      else
        @logger&.call("Ignoring missing browser #{path}; run `script/install-chromium` to reinstall it")
        nil
      end
    end

    def warn_about(path)
      @logger&.call("Using browser at #{path}")
      return unless path.include?("Brave")

      @logger&.call("Warning: Brave blocks many third-party tracking cookies and caps the lifetime of " \
                    "JavaScript-set cookies; run `script/install-chromium` for a complete and accurate scan")
    end

    # Navigates via the block and waits for the page to settle.
    # @return [String, nil] a non-fatal load error
    def load
      @ferrum.network.clear(:traffic)
      error = begin
        yield
        nil
      rescue Ferrum::PendingConnectionsError => e
        # The document loaded but some resources did not; cookies are still useful.
        e.message
      end
      settle
      error
    end

    # Waits until neither the network nor the cookie jar changed for
    # settle_time seconds, but at most max_settle_time seconds.
    #
    # Waiting for the network to be idle is not enough: tag managers load tags
    # in waves (container script, then tags, then the scripts those tags load),
    # often from timers, and the network is idle in between. Requests that stay
    # open (long polling, streaming) do not keep the page from settling, only
    # requests starting or finishing do.
    def settle
      return unless @settle_time.positive?

      deadline = monotonic + @max_settle_time
      quiet_since = monotonic
      last = activity
      until monotonic - quiet_since >= @settle_time || monotonic >= deadline
        sleep(SETTLE_POLL_INTERVAL)
        current = activity
        next if current == last

        last = current
        quiet_since = monotonic
      end
    end

    def activity
      network = @ferrum.network
      cookies = all_cookies.map { |c| c.values_at("name", "domain", "path", "value") }.sort
      [network.total_connections, network.finished_connections, cookies]
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def all_cookies
      @ferrum.page.command("Network.getAllCookies")["cookies"]
    end

    def collect_links
      Array(@ferrum.evaluate(LINKS_JS)).map { |href, url| { href: href, url: url } }
    rescue Ferrum::Error
      []
    end

    def safe_cookies
      all_cookies
    rescue Ferrum::Error
      []
    end
  end
end
