# frozen_string_literal: true

require "webrick"
require "json"
require "cgi"
require "timeout"
require "ferrum"

# The consent banner (assets/cookiejar-consent.js) in a real headless browser.
# Uses BROWSER_PATH, else the Chromium installed by the scanner's
# script/install-chromium, else whatever Chrome Ferrum finds.
RSpec.describe "cookie consent banner", :browser do
  # The analytics tag only runs with consent and sets _ga.
  PAGE = lambda do |head: "", lang: "en"|
    <<~HTML
      <!doctype html><html lang="#{lang}"><head>
      #{head}
      <script src="/banner.js"></script>
      <script>window.consentAtTagLoad = JSON.parse(JSON.stringify(window.dataLayer.map(function (e) {
        return Object.prototype.toString.call(e) === "[object Arguments]" ? Array.from(e) : e;
      })));</script>
      <script type="text/plain" data-cookie-category="performance">
        document.cookie = "_ga=GA1.1.1; path=/"; window.analyticsRuns = (window.analyticsRuns || 0) + 1;
      </script>
      </head><body><a href="#" id="settings" data-cookiejar-preferences>Cookie settings</a></body></html>
    HTML
  end

  before(:all) do
    script = CookiejarConsent::Builder.new(fixture_report,
                                           options: { "privacyPolicyUrl" => "/privacy", "recordUrl" => "/consents" })
                                      .render("js")
    @records = Queue.new

    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    serve = lambda do |type, body|
      lambda do |_req, res|
        res["Content-Type"] = type
        res.body = body
      end
    end
    @server.mount_proc("/banner.js", serve.call("text/javascript", script))
    @server.mount_proc("/", serve.call("text/html", PAGE.call))
    @server.mount_proc("/consents") do |req, res|
      @records << { type: req["Content-Type"], body: JSON.parse(req.body) }
      res.status = 204
    end
    @server.mount_proc("/de", serve.call("text/html", PAGE.call(lang: "de")))
    @server.mount_proc("/revised", serve.call("text/html", PAGE.call(head: <<~HTML)))
      <script>window.cookiejarConsentConfig = { revision: 2 };</script>
    HTML
    @thread = Thread.new { @server.start }
    @base = "http://127.0.0.1:#{@server.config[:Port]}"
    @page = Ferrum::Browser.new(headless: true, timeout: 10, process_timeout: 30, browser_path: browser_path)
  end

  after(:all) do
    @page&.quit
    @server&.shutdown
    @thread&.join
  end

  def browser_path
    installed = File.expand_path("../../scanner/vendor/chromium/browser-path", __dir__)
    path = File.read(installed).strip if File.file?(installed)
    ENV.fetch("BROWSER_PATH", nil) || (path if path && File.executable?(path))
  end

  before do
    @page.cookies.clear
    @records.clear
  end

  def next_record
    Timeout.timeout(3) { @records.pop }
  end

  def visit(path = "/") = @page.go_to("#{@base}#{path}")
  def js(expression) = @page.evaluate(expression)
  def shadow(selector) = "document.getElementById('cookiejar-consent').shadowRoot.querySelector(#{selector.to_json})"
  def click(selector) = js("#{shadow(selector)}.click()")
  def visible?(selector) = js("!!document.getElementById('cookiejar-consent') && !!#{shadow(selector)}")

  def wait_for
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    until (result = yield)
      raise "timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
    result
  end

  def data_layer
    js(<<~JS)
      window.dataLayer.map(function (e) {
        return Object.prototype.toString.call(e) === "[object Arguments]" ? Array.from(e) : e;
      })
    JS
  end

  def consent_updates = data_layer.select { |e| e.is_a?(Array) && e[0..1] == %w[consent update] }.map(&:last)
  def stored_consent = JSON.parse(CGI.unescape(@page.cookies["cookiejar_consent"].value))
  def cookie?(name) = !@page.cookies[name].nil?

  def open_preferences
    js("document.getElementById('settings').click()")
    wait_for { js("!!document.getElementById('cookiejar-consent') && !!#{shadow("dialog[open]")}") }
  end

  it "denies optional consent by default before any tag loads and asks the visitor" do
    visit
    defaults = js("window.consentAtTagLoad")
    expect(defaults[0]).to eq(["consent", "default", {
                                 "functionality_storage" => "granted", "personalization_storage" => "granted",
                                 "security_storage" => "granted", "analytics_storage" => "denied",
                                 "ad_storage" => "denied", "ad_user_data" => "denied",
                                 "ad_personalization" => "denied", "wait_for_update" => 500
                               }])
    expect(defaults[1]).to eq(["set", "ads_data_redaction", true])
    expect(wait_for { visible?(".banner") }).to be(true)
    expect(js(%(#{shadow(".banner")}.textContent))).to include("We use cookies", "Accept all", "Reject all",
                                                                     "Privacy policy")
    expect(js("window.analyticsRuns")).to be_nil
  end

  it "stores a rejection, keeps tags blocked and applies the choice on the next page before tags load" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=reject-all]")

    expect(visible?(".banner")).to be(false)
    expect(stored_consent["categories"]).to eq("functionality" => true, "performance" => false,
                                               "marketing" => false, "unknown" => false)
    expect(consent_updates.last).to include("analytics_storage" => "denied", "ad_storage" => "denied")
    expect(data_layer.last).to include("event" => "cookie_consent_update", "cookie_consent_source" => "reject_all")

    visit
    expect(js("window.consentAtTagLoad")[2]).to eq(["consent", "update", {
                                                     "functionality_storage" => "granted",
                                                     "personalization_storage" => "granted",
                                                     "security_storage" => "granted",
                                                     "analytics_storage" => "denied", "ad_storage" => "denied",
                                                     "ad_user_data" => "denied", "ad_personalization" => "denied"
                                                   }])
    sleep 0.2
    expect(visible?(".banner")).to be(false)
    expect(js("window.analyticsRuns")).to be_nil
  end

  it "runs consent-gated tags and grants Google consent when all are accepted" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=accept-all]")

    expect(js("window.analyticsRuns")).to eq(1)
    expect(cookie?("_ga")).to be(true)
    expect(consent_updates.last.values.uniq).to eq(["granted"])

    visit
    expect(js("window.analyticsRuns")).to eq(1)
  end

  it "lists the report's cookies by category and saves a custom selection" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=customize]")
    wait_for { visible?("dialog[open]") }

    sections = js(<<~JS)
      Array.from(#{shadow("dialog")}.querySelectorAll("section.category")).map(function (s) {
        return [s.dataset.category, Array.from(s.querySelectorAll("td.name")).map(function (td) { return td.textContent; })];
      })
    JS
    expect(sections).to eq([["functionality", ["PHPSESSID"]], ["performance", ["_ga"]], ["marketing", %w[_fbp IDE]],
                            ["unknown", ["mystery_x"]]])
    expect(js(%(#{shadow('section[data-category="functionality"]')}.textContent))).to include("Always active")

    click('input[data-category="performance"]')
    click("[data-action=save]")

    expect(visible?("dialog")).to be(false)
    expect(stored_consent["categories"]).to include("performance" => true, "marketing" => false)
    expect(consent_updates.last).to include("analytics_storage" => "granted", "ad_storage" => "denied")
    expect(js("window.analyticsRuns")).to eq(1)
  end

  it "deletes the cookies of a withdrawn category" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=accept-all]")
    expect(cookie?("_ga")).to be(true)

    open_preferences
    expect(js(%(#{shadow('input[data-category="performance"]')}.checked))).to be(true)
    click('input[data-category="performance"]')
    click("[data-action=save]")

    expect(cookie?("_ga")).to be(false)
    expect(consent_updates.last).to include("analytics_storage" => "denied", "ad_storage" => "granted")
  end

  it "sends a record of each decision to the consent log" do
    visit("/?utm_source=newsletter&email=a@b.example#top")
    wait_for { visible?(".banner") }
    click("[data-action=accept-all]")

    sent = next_record
    expect(sent[:type]).to match(%r{\Atext/plain;charset=utf-8\z}i)
    record = sent[:body]
    expect(record).to include(
      "id" => stored_consent["id"], "timestamp" => stored_consent["updated"], "action" => "accept_all",
      "categories" => { "functionality" => true, "performance" => true, "marketing" => true, "unknown" => true },
      "revision" => "1", "url" => "#{@base}/", "language" => "en", "bannerVersion" => "1"
    )
    expect(record["report"]).to match(/\Acookies-.*\.csv\z/)
    expect(record["fingerprint"]).to match(/\A\h{16}\z/)

    open_preferences
    click('input[data-category="marketing"]')
    click("[data-action=save]")
    expect(next_record[:body]).to include("id" => record["id"], "action" => "custom",
                                          "categories" => hash_including("marketing" => false))

    visit
    sleep 0.2
    expect(@records).to be_empty
  end

  it "asks again when the revision changes" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=accept-all]")
    visit
    sleep 0.2
    expect(visible?(".banner")).to be(false)

    visit("/revised")
    expect(wait_for { visible?(".banner") }).to be(true)
  end

  it "brings the banner back when the settings are closed without a choice" do
    visit
    wait_for { visible?(".banner") }
    click("[data-action=customize]")
    wait_for { visible?("dialog[open]") }
    click("[data-action=close]")

    expect(wait_for { visible?(".banner") }).to be(true)
    expect(@page.cookies["cookiejar_consent"]).to be_nil
  end

  it "uses the page language" do
    visit("/de")
    wait_for { visible?(".banner") }
    expect(js(%(#{shadow(".banner")}.textContent))).to include("Wir verwenden Cookies", "Alle akzeptieren",
                                                                     "Alle ablehnen")
  end
end
