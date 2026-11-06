# frozen_string_literal: true

RSpec.describe Cookiejar::Crawler do
  # Serves a static site map: url => { links: [href...], cookies: [names] }
  class FakeBrowser
    attr_reader :visited

    def initialize(site)
      @site = site
      @visited = []
    end

    def visit(url)
      @visited << url
      page = @site.fetch(url) { return Cookiejar::Browser::PageResult.new(url: url, final_url: url, cookies: [], links: [], error: "404") }
      final_url = page.fetch(:redirect_to, url)
      page = @site.fetch(final_url, page) if page.key?(:redirect_to)
      links = page.fetch(:links, []).map { |href| { href: href, url: URI.join(final_url, href).to_s } }
      Cookiejar::Browser::PageResult.new(url: url, final_url: final_url, cookies: page.fetch(:cookies, []), links: links)
    end
  end

  include CookieHelpers

  let(:site) do
    {
      "https://example.com/" => { links: ["/a", "/b#frag", "https://other.org/", "mailto:x@y.z"],
                                  cookies: [raw_cookie("session")] },
      "https://example.com/a" => { links: ["/a/deep", "/"], cookies: [raw_cookie("session"), raw_cookie("_ga")] },
      "https://example.com/b" => { links: [], cookies: [raw_cookie("_fbp")] },
      "https://example.com/a/deep" => { links: [], cookies: [raw_cookie("deep")] }
    }
  end
  let(:browser) { FakeBrowser.new(site) }
  let(:filter) { Cookiejar::LinkFilter.new(allowed_domains: ["example.com"]) }

  def crawl(**opts)
    described_class.new(browser: browser, link_filter: filter, **opts).crawl(["https://example.com/"])
  end

  it "follows links breadth-first up to the configured depth" do
    crawler = crawl(depth: 1)
    expect(browser.visited).to eq(["https://example.com/", "https://example.com/a", "https://example.com/b"])
    expect(crawler.cookies.values.map(&:name)).to contain_exactly("session", "_ga", "_fbp")
  end

  it "goes deeper when asked" do
    crawl(depth: 2)
    expect(browser.visited).to include("https://example.com/a/deep")
    expect(browser.visited.count("https://example.com/")).to eq(1)
  end

  it "only visits start URIs when link following is disabled" do
    crawl(follow_links: false, depth: 5)
    expect(browser.visited).to eq(["https://example.com/"])
  end

  it "stops at max pages" do
    crawl(depth: 5, max_pages: 2)
    expect(browser.visited.size).to eq(2)
  end

  it "deduplicates cookies and tracks the pages they were seen on" do
    session = crawl(depth: 1).cookies.values.find { |c| c.name == "session" }
    expect(session.first_seen_on).to eq("https://example.com/")
    expect(session.seen_on).to eq(["https://example.com/", "https://example.com/a"])
  end

  it "records page errors without aborting" do
    site["https://example.com/"][:links] << "/missing"
    crawler = crawl(depth: 1)
    expect(crawler.pages.find { |p| p[:url] == "https://example.com/missing" }[:error]).to eq("404")
  end

  describe "unique visits" do
    def crawl_from(start_uris, **opts)
      described_class.new(browser: browser, link_filter: filter, **opts).crawl(start_uris)
    end

    it "visits duplicate and equivalent start URIs once" do
      crawler = crawl_from(["https://example.com/", "https://EXAMPLE.com", "https://example.com:443/#top"],
                           follow_links: false)
      expect(browser.visited).to eq(["https://example.com/"])
      expect(crawler.pages.size).to eq(1)
    end

    it "does not revisit pages linked from several places or with different fragments" do
      site["https://example.com/b"][:links] = ["/a#section", "/", "https://Example.com/a"]
      crawl(depth: 3)
      expect(browser.visited.tally.values).to all(eq(1))
    end

    it "skips a queued URL that an earlier page already redirected to" do
      site["https://example.com/"][:links] = ["/old", "/b"]
      site["https://example.com/old"] = { redirect_to: "https://example.com/b" }
      crawler = crawl(depth: 1)
      expect(browser.visited).to eq(["https://example.com/", "https://example.com/old"])
      expect(crawler.pages.map { |p| p[:final_url] }).to eq(["https://example.com/", "https://example.com/b"])
    end

    it "does not count skipped duplicates towards max pages" do
      site["https://example.com/"][:links] = ["/old", "/b", "/a"]
      site["https://example.com/old"] = { redirect_to: "https://example.com/b" }
      crawl(depth: 1, max_pages: 3)
      expect(browser.visited).to eq(["https://example.com/", "https://example.com/old", "https://example.com/a"])
    end
  end
end
