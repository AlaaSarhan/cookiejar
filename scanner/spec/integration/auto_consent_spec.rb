# frozen_string_literal: true

require "webrick"
require "csv"

# Accepting cookie consent banners in a real headless browser.
# Every page sets the marketing cookie _fbp only once consent was given.
RSpec.describe "accepting cookie consent", :browser do
  GATED_TAG = <<~HTML
    <script>
      if (document.cookie.includes("consent_given=1")) document.cookie = "_fbp=fb.1.123; max-age=7776000; path=/";
      function giveConsent() { document.cookie = "consent_given=1; path=/"; }
    </script>
  HTML

  before(:all) do
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    port = @server.config[:Port]
    page = lambda do |body|
      lambda do |_req, res|
        res["Content-Type"] = "text/html"
        res.body = "<!doctype html><html><head>#{GATED_TAG}</head><body>#{body}</body></html>"
      end
    end

    # A known platform's banner, injected after the load event like most CMPs do.
    @server.mount_proc("/known", page.call(<<~HTML))
      <script>
        setTimeout(() => {
          if (document.cookie.includes("consent_given=1")) return;
          const banner = document.createElement("div");
          banner.innerHTML = '<button id="onetrust-accept-btn-handler">Yes</button>';
          banner.querySelector("button").onclick = () => { giveConsent(); banner.remove(); };
          document.body.appendChild(banner);
        }, 400);
      </script>
    HTML
    @server.mount_proc("/text", page.call(<<~HTML))
      <div class="site-cookie-bar">
        <p>We use cookies.</p>
        <button onclick="document.cookie = 'clicked_settings=1'">Cookie settings</button>
        <button onclick="document.cookie = 'clicked_reject=1'">Reject all</button>
        <button onclick="document.cookie = 'clicked_necessary=1'">Accept only necessary</button>
        <button onclick="giveConsent()">Accept all</button>
      </div>
    HTML
    @server.mount_proc("/no-accept-all", page.call(<<~HTML))
      <div id="cookie-notice">
        <button onclick="giveConsent()">Accept necessary cookies only</button>
        <button onclick="giveConsent()">Continue without accepting</button>
        <button onclick="giveConsent()">Allow selection</button>
      </div>
    HTML
    @server.mount_proc("/shadow", page.call(<<~HTML))
      <div id="host"></div>
      <script>
        const root = document.getElementById("host").attachShadow({ mode: "open" });
        root.innerHTML = '<div style="position: fixed; bottom: 0"><button>Alle akzeptieren</button></div>';
        root.querySelector("button").onclick = giveConsent;
      </script>
    HTML
    # Served from another origin (localhost vs 127.0.0.1), like hosted CMP frames.
    @server.mount_proc("/iframe", page.call(<<~HTML))
      <iframe src="http://localhost:#{port}/consent-frame"></iframe>
      <script>window.addEventListener("message", (e) => { if (e.data === "accept") giveConsent(); });</script>
    HTML
    @server.mount_proc("/consent-frame") do |_req, res|
      res["Content-Type"] = "text/html"
      res.body = %(<button onclick="parent.postMessage('accept', '*')">I agree</button>)
    end
    @server.mount_proc("/custom", page.call(<<~HTML))
      <span class="weird-yes" onclick="giveConsent()">Fine by me</span>
    HTML
    @server.mount_proc("/not-a-banner", page.call(<<~HTML))
      <form><p>Subscribe to our newsletter</p><button type="button" onclick="giveConsent()">OK</button></form>
    HTML
    @thread = Thread.new { @server.start }
    @base = "http://127.0.0.1:#{port}"
  end

  after(:all) do
    @server&.shutdown
    @thread&.join
  end

  def visit(path, consent: Cookiejar::AutoConsent.new(wait: 2))
    browser = Cookiejar::Browser.new(settle_time: 0.1, consent: consent)
    browser.visit("#{@base}#{path}")
  ensure
    browser&.close
  end

  def cookie_names(result) = result.cookies.map { |c| c["name"] }.uniq

  it "accepts banners of known consent platforms that appear after the page loaded" do
    result = visit("/known")
    expect(result.consent).to eq("OneTrust (#onetrust-accept-btn-handler)")
    expect(cookie_names(result)).to include("consent_given", "_fbp")
  end

  it "clicks the accept-all button of an unknown banner and leaves the other buttons alone" do
    result = visit("/text")
    expect(result.consent).to eq('button "Accept all"')
    expect(cookie_names(result)).to contain_exactly("consent_given", "_fbp")
  end

  it "never clicks buttons that reject or only partially accept" do
    result = visit("/no-accept-all", consent: Cookiejar::AutoConsent.new(wait: 0))
    expect(result.consent).to be_nil
    expect(cookie_names(result)).to be_empty
  end

  it "finds banners inside open shadow roots" do
    result = visit("/shadow")
    expect(result.consent).to eq('button "Alle akzeptieren"')
    expect(cookie_names(result)).to include("_fbp")
  end

  it "finds banners inside cross-origin iframes" do
    result = visit("/iframe")
    expect(result.consent).to start_with('button "I agree" in frame http://localhost:')
    expect(cookie_names(result)).to include("_fbp")
  end

  it "clicks custom selectors" do
    result = visit("/custom", consent: Cookiejar::AutoConsent.new(selectors: [".weird-yes"], wait: 0))
    expect(result.consent).to eq("selector .weird-yes")
    expect(cookie_names(result)).to include("_fbp")
  end

  it "ignores accept-like buttons outside of anything that looks like a consent banner" do
    result = visit("/not-a-banner", consent: Cookiejar::AutoConsent.new(wait: 0))
    expect(result.consent).to be_nil
    expect(cookie_names(result)).to be_empty
  end

  it "only waits for a banner on the first page of each host" do
    consent = Cookiejar::AutoConsent.new(wait: 1.5)
    browser = Cookiejar::Browser.new(settle_time: 0, consent: consent)
    first = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    browser.visit("#{@base}/not-a-banner")
    second = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    browser.visit("#{@base}/custom")
    done = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect(second - first).to be >= 1.5
    expect(done - second).to be < 1.0
  ensure
    browser&.close
  end

  it "reports consent-gated cookies through the CLI unless disabled" do
    scan = lambda do |*args|
      dir = Dir.mktmpdir
      status = Cookiejar::CLI.start([*args, "-o", dir, "--settle", "0.1", "--no-follow-links", "#{@base}/text"],
                                       out: StringIO.new, err: StringIO.new)
      expect(status).to eq(0)
      CSV.read(Cookiejar::Report.files_in(dir).last, headers: true)
         .select { |row| row["category"] == "marketing" }.map { |row| row["cookie name"] }
    end

    expect(scan.call).to eq(["_fbp"])
    expect(scan.call("--no-accept-consent")).to be_empty
  end
end
