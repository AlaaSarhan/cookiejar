# frozen_string_literal: true

require "webrick"

# Waiting for pages to settle in a real headless browser: tag managers load tags
# in several waves, with pauses between them in which the network is idle.
RSpec.describe "waiting for pages to settle", :browser do
  # Loads like Google Tag Manager: the container script arrives with a delay,
  # then fires tags one after another, each loading its own (slow) script.
  TAG_MANAGER = <<~HTML
    <script>
      function loadScript(src) {
        const s = document.createElement("script");
        s.src = src;
        document.head.appendChild(s);
      }
      function tagManager() { setTimeout(() => loadScript("/gtm.js"), 300); }
    </script>
  HTML

  before(:all) do
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    script = lambda do |body, delay: 0.3|
      lambda do |_req, res|
        sleep(delay)
        res["Content-Type"] = "application/javascript"
        res.body = body
      end
    end
    @server.mount_proc("/gtm.js", script.call(<<~JS))
      setTimeout(() => loadScript("/tag-1.js"), 500);
    JS
    @server.mount_proc("/tag-1.js", script.call(<<~JS))
      document.cookie = "_gcl_au=1.1.1; max-age=7776000; path=/";
      setTimeout(() => loadScript("/tag-2.js"), 500);
    JS
    @server.mount_proc("/tag-2.js", script.call(<<~JS))
      document.cookie = "_fbp=fb.1.123; max-age=7776000; path=/";
    JS
    @server.mount_proc("/consent-log", script.call("", delay: 0.4))

    page = lambda do |body|
      lambda do |_req, res|
        res["Content-Type"] = "text/html"
        res.body = "<!doctype html><html><head>#{TAG_MANAGER}</head><body>#{body}</body></html>"
      end
    end
    @server.mount_proc("/tags", page.call("<script>window.addEventListener('load', tagManager);</script>"))
    # A consent platform that only stores consent after its server logged it,
    # with tags gated on the stored consent.
    @server.mount_proc("/slow-consent", page.call(<<~HTML))
      <div id="cookie-banner"><button id="accept">Accept all cookies</button></div>
      <script>
        const banner = document.getElementById("cookie-banner");
        if (document.cookie.includes("consent=1")) {
          banner.remove();
          window.addEventListener("load", tagManager);
        }
        document.getElementById("accept").onclick = () => {
          banner.remove();
          setTimeout(() => fetch("/consent-log").then(() => { document.cookie = "consent=1; path=/"; }), 300);
        };
      </script>
    HTML
    @thread = Thread.new { @server.start }
    @base = "http://127.0.0.1:#{@server.config[:Port]}"
  end

  after(:all) do
    @server&.shutdown
    @thread&.join
  end

  def visit(path, consent: nil)
    browser = Cookiejar::Browser.new(settle_time: 1, max_settle_time: 10, consent: consent)
    browser.visit("#{@base}#{path}")
  ensure
    browser&.close
  end

  def cookie_names(result) = result.cookies.map { |c| c["name"] }.uniq

  it "waits for tags that a tag manager loads in several waves" do
    expect(cookie_names(visit("/tags"))).to include("_gcl_au", "_fbp")
  end

  it "waits for consent to be stored before reloading the page" do
    result = visit("/slow-consent", consent: Cookiejar::AutoConsent.new(wait: 0))
    expect(result.consent).to eq('button "Accept all cookies"')
    expect(cookie_names(result)).to include("consent", "_gcl_au", "_fbp")
  end

  it "gives up waiting after the maximum settle time" do
    browser = Cookiejar::Browser.new(settle_time: 1, max_settle_time: 1.2)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = browser.visit("#{@base}/tags")
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 2
    expect(result.cookies.map { |c| c["name"] }).not_to include("_fbp")
  ensure
    browser&.close
  end
end
