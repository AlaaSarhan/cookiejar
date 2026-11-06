# frozen_string_literal: true

RSpec.describe Cookiejar::CookieDatabase do
  subject(:database) { described_class.new(path) }

  let(:path) do
    File.join(Dir.mktmpdir, "ocd.csv").tap do |file|
      File.write(file, <<~CSV)
        ID,Platform,Category,Cookie / Data Key name,Domain,Description,Retention period,Data Controller,User Privacy & GDPR Rights Portals,Wildcard match
        1,Acme Ads,Marketing,acme_id,acme-ads.com (3rd party) or .acme.net (3rd party),Identifies visitors for ads,1 year,Acme,https://acme.example/privacy,0
        2,Acme Analytics,Analytics,_acme_,,Acme Analytics session,session,Acme,,1
        3,Acme Analytics,Analytics,_acme_long_,,Acme Analytics long prefix,,Acme,,1
        4,Ad Server,Marketing,IDE,adserver.com (3rd party),Ad targeting,2 years,Ad Server,,0
        5,Social,Marketing,locale,social.com (3rd party),Language for social widgets,,Social,,0
        6,Shop,Functional,cart,,Shopping cart,,Shop,,0
        7,Store,Security,XSRF-STORE,,Request forgery protection,,Store,,0
        8,Other,Unclassified,odd,,,,,,0
      CSV
    end
  end

  def lookup(name, domain: "example.com") = database.lookup(cookie_record(name, domain: domain))

  it "loads entries with a known category" do
    expect(database.size).to eq(7)
  end

  it "matches exact names, with higher confidence on the entry's domains" do
    expect(lookup("acme_id")).to have_attributes(category: "marketing", confidence: 0.9)
    expect(lookup("acme_id", domain: ".track.acme.net").confidence).to eq(0.95)
    expect(lookup("acme_id").entry).to have_attributes(platform: "Acme Ads", domains: %w[acme-ads.com acme.net])
    expect(lookup("acme_idx")).to be_nil
  end

  it "matches wildcard entries by prefix, preferring the longest prefix" do
    expect(lookup("_acme_123")).to have_attributes(category: "performance", confidence: 0.85)
    expect(lookup("_acme_long_1").entry.description).to eq("Acme Analytics long prefix")
  end

  it "needs a matching domain for generic names" do
    expect(lookup("IDE").confidence).to eq(0.6)
    expect(lookup("IDE", domain: "adserver.com").confidence).to eq(0.95)
    expect(lookup("locale").confidence).to eq(0.6)
    expect(lookup("cart").confidence).to eq(0.9) # a plain word, but not tied to a platform's domain
  end

  it "maps the database categories" do
    expect(lookup("cart").category).to eq("functionality")
    expect(lookup("XSRF-STORE").category).to eq("functionality")
  end

  it "reports a missing database file" do
    expect { described_class.new("/missing/ocd.csv") }.to raise_error(Cookiejar::Error, /not found/)
  end
end
