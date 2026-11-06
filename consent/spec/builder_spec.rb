# frozen_string_literal: true

require "json"

RSpec.describe CookiejarConsent::Builder do
  let(:dir) { Dir.mktmpdir }
  let(:report) { fixture_report }

  it "groups the report's cookies by category, once per name and domain" do
    cookies = described_class.new(report).cookies

    expect(cookies.keys).to eq(CookiejarConsent::CATEGORIES)
    expect(cookies["functionality"].map { |c| c["name"] }).to eq(["PHPSESSID"])
    expect(cookies["performance"]).to eq([{
                                           "name" => "_ga", "domain" => "example.com", "path" => "/",
                                           "party" => "first", "provider" => "Google Analytics",
                                           "description" => "Google Analytics: distinguishes unique visitors.",
                                           "duration" => "3 months"
                                         }])
    expect(cookies["marketing"].map { |c| [c["name"], c["party"]] }).to eq([%w[_fbp first], %w[IDE third]])
    expect(cookies["unknown"].map { |c| c["name"] }).to eq(["mystery_x"])
  end

  it "can list unclassified cookies in another category" do
    cookies = described_class.new(report, unknown: "marketing").cookies
    expect(cookies["marketing"].map { |c| c["name"] }).to eq(%w[_fbp IDE mystery_x])
    expect(cookies["unknown"]).to be_empty
    expect { described_class.new(report, unknown: "functionality") }.to raise_error(CookiejarConsent::Error)
  end

  it "writes the cookie list and options as JSON" do
    json = JSON.parse(described_class.new(report, options: { "revision" => 3 }).render("json"))
    expect(json).to include("revision" => 3, "cookies" => hash_including("marketing"))
    expect(json["source"]["report"]).to eq(File.basename(report))
  end

  it "builds the config into the banner script, safe to inline in HTML" do
    options = { "texts" => { "bannerTitle" => "</script><b>hi</b>" } }
    js = described_class.new(report, options: options).render("js")

    expect(js).not_to include(described_class::PLACEHOLDER)
    expect(js).not_to include("</script>")
    embedded = js[/var EMBEDDED_CONFIG = (.*);$/, 1]
    expect(JSON.parse(embedded)).to include("texts" => options["texts"], "cookies" => hash_including("performance"))
  end

  it "rejects files that are not reports" do
    path = File.join(dir, "other.csv")
    File.write(path, "a,b\n1,2\n")
    expect { described_class.new(path).cookies }.to raise_error(CookiejarConsent::Error, /not a cookie report/)
    expect { described_class.new(File.join(dir, "nope.csv")).cookies }.to raise_error(CookiejarConsent::Error, /not found/)
  end

  it "loads banner options from YAML" do
    path = File.join(dir, "banner.yml")
    File.write(path, "revision: 2\nprivacyPolicyUrl: /privacy\n")
    expect(described_class.load_options(path)).to eq("revision" => 2, "privacyPolicyUrl" => "/privacy")
    File.write(path, "- nope\n")
    expect { described_class.load_options(path) }.to raise_error(CookiejarConsent::Error, /must be a mapping/)
  end
end
