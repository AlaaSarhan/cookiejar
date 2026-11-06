# frozen_string_literal: true

RSpec.describe Cookiejar::LinkFilter do
  def filter(**opts)
    described_class.new(allowed_domains: ["example.com"], **opts)
  end

  it "follows links on allowed domains and their subdomains" do
    f = filter
    expect(f.follow?(href: "/a", url: "https://example.com/a")).to be true
    expect(f.follow?(href: "x", url: "https://shop.example.com/x")).to be true
    expect(f.follow?(href: "x", url: "https://notexample.com/x")).to be false
    expect(f.follow?(href: "x", url: "https://other.org/x")).to be false
  end

  it "accepts *. and leading-dot domain notations" do
    f = described_class.new(allowed_domains: ["*.Example.com", ".other.org"])
    expect(f.follow?(href: "x", url: "https://www.example.com/")).to be true
    expect(f.follow?(href: "x", url: "https://other.org/")).to be true
  end

  it "ignores non-http links and garbage" do
    f = filter
    expect(f.follow?(href: "mailto:a@example.com", url: "mailto:a@example.com")).to be false
    expect(f.follow?(href: "javascript:void(0)", url: "javascript:void(0)")).to be false
    expect(f.follow?(href: "x", url: "http://exa mple.com")).to be false
  end

  it "applies href include and exclude patterns to the raw attribute value" do
    f = filter(include_hrefs: ["/products/**"], exclude_hrefs: ["**?print=1"])
    expect(f.follow?(href: "/products/a/b", url: "https://example.com/products/a/b")).to be true
    expect(f.follow?(href: "https://example.com/products/a", url: "https://example.com/products/a")).to be false
    expect(f.follow?(href: "/products/a?print=1", url: "https://example.com/products/a?print=1")).to be false
  end

  it "applies path include and exclude patterns to the resolved URL path" do
    f = filter(include_paths: ["/blog/**", "/"], exclude_paths: ["/blog/drafts/**"])
    expect(f.follow?(href: "https://example.com", url: "https://example.com")).to be true
    expect(f.follow?(href: "../blog/x", url: "https://example.com/blog/2024/x")).to be true
    expect(f.follow?(href: "x", url: "https://example.com/blog/drafts/x")).to be false
    expect(f.follow?(href: "x", url: "https://example.com/shop")).to be false
  end

  it "defaults allowed domains to the start URI hosts" do
    config = Cookiejar::Config.new(start_uris: ["https://www.example.com/start", "http://other.org"])
    f = described_class.from_config(config)
    expect(f.follow?(href: "x", url: "https://www.example.com/x")).to be true
    expect(f.follow?(href: "x", url: "https://example.com/x")).to be false
    expect(f.follow?(href: "x", url: "https://other.org/x")).to be true
  end
end
