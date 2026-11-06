# frozen_string_literal: true

require "webrick"
require "csv"
require "json"

# End-to-end scan against a local site using the real headless browser.
# Skip with SKIP_BROWSER_SPECS=1 where no Chromium-based browser is installed.
RSpec.describe "scanning a website", :browser do
  before(:all) do
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    page = lambda do |body, cookie: nil|
      lambda do |_req, res|
        res["Content-Type"] = "text/html"
        res["Set-Cookie"] = cookie if cookie
        res.body = "<!doctype html><html><body>#{body}</body></html>"
      end
    end
    @server.mount_proc("/", page.call(<<~HTML, cookie: "PHPSESSID=abc; Path=/; HttpOnly; SameSite=Lax"))
      <a href="/blog/post">post</a> <a href="/admin/panel">admin</a> <a href="/file.pdf">pdf</a>
      <script>document.cookie = "_ga=GA1.1.123.456; max-age=7776000; path=/";</script>
    HTML
    @server.mount_proc("/blog/post", page.call(<<~HTML))
      <a href="/blog/deeper">deeper</a>
      <script>document.cookie = "mystery_x=1; path=/";</script>
    HTML
    @server.mount_proc("/blog/deeper", page.call("<script>document.cookie = 'deep=1';</script>"))
    @server.mount_proc("/admin/panel", page.call("", cookie: "admin_seen=1; Path=/"))
    @server.mount_proc("/file.pdf", page.call("", cookie: "pdf_seen=1; Path=/"))
    @thread = Thread.new { @server.start }
    @base = "http://127.0.0.1:#{@server.config[:Port]}"
  end

  after(:all) do
    @server&.shutdown
    @thread&.join
  end

  let(:output_dir) { Dir.mktmpdir }

  def scan(*args)
    out = StringIO.new
    status = Cookiejar::CLI.start([*args, "-o", output_dir, "--settle", "0.2", "#{@base}/"], out: out,
                                                                                               err: StringIO.new)
    expect(status).to eq(0)
    rows = CSV.read(Cookiejar::Report.files_in(output_dir).last, headers: true)
    Cookiejar::CATEGORIES.to_h do |cat|
      [cat, rows.select { |r| r["category"] == cat }.to_h { |r| [r["cookie name"], r] }]
    end
  end

  it "captures header and JavaScript cookies, follows filtered links and categorises them" do
    report = scan("--exclude-path", "/admin/**", "--exclude-href", "**.pdf", "--depth", "1")

    expect(report["functionality"].keys).to eq(["PHPSESSID"])
    expect(report["functionality"]["PHPSESSID"]["security settings"]).to eq("HttpOnly; SameSite=Lax")
    expect(report["performance"].keys).to eq(["_ga"])
    expect(report["performance"]["_ga"]["storage duration"]).to eq("3 months")
    expect(report["unknown"].keys).to eq(["mystery_x"])
    expect(JSON.parse(report["unknown"]["mystery_x"]["full details"])["firstSeenOn"]).to eq("#{@base}/blog/post")
  end

  it "visits only the start URI when link following is disabled" do
    report = scan("--no-follow-links")
    expect(report.values.flat_map(&:keys)).to contain_exactly("PHPSESSID", "_ga")
  end
end
