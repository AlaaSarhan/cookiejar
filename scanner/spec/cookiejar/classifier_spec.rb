# frozen_string_literal: true

RSpec.describe Cookiejar::Classifier do
  subject(:classifier) { described_class.new(cookie_database: cookie_database) }

  let(:cookie_database) { Cookiejar::CookieDatabase.new(File.expand_path("../fixtures/open-cookie-database.csv", __dir__)) }

  def classify(name, **attrs)
    classifier.classify(cookie_record(name, **attrs))
  end

  it "classifies well-known cookies by name" do
    expect(classify("_ga")).to have_attributes(category: "performance", provider: "Google Analytics")
    expect(classify("_ga_ABC123").category).to eq("performance")
    expect(classify("_fbp").category).to eq("marketing")
    expect(classify("PHPSESSID").category).to eq("functionality")
    expect(classify("OptanonConsent").category).to eq("functionality")
    expect(classify("_hjSessionUser_12345")).to have_attributes(category: "performance", confidence: 0.95)
  end

  it "falls back to the Open Cookie Database for names without a built-in rule" do
    result = classify("ARRAffinity")
    expect(result).to have_attributes(category: "functionality", provider: /Azure/, source: "open-cookie-database")
    expect(result.to_h["openCookieDatabase"]).to include("platform" => /Azure/, "category" => "Functional")
  end

  it "keeps built-in rules ahead of the Open Cookie Database and adds its entry as reference" do
    result = classify("_ga")
    expect(result).to have_attributes(source: "builtin:name", description: "Google Analytics: distinguishes unique visitors.")
    expect(result.open_cookie_database).to include("platform" => "Google Analytics")
  end

  it "only suggests a category for generic database names on other domains" do
    expect(classify("locale")).to have_attributes(category: "unknown", suggested_category: "marketing")
  end

  it "can classify without the Open Cookie Database" do
    expect(described_class.new(cookie_database: nil).classify(cookie_record("ARRAffinity")).category).to eq("unknown")
  end

  it "only applies domain-restricted name rules on matching domains" do
    expect(classify("IDE", domain: ".doubleclick.net").category).to eq("marketing")
    expect(classify("IDE", domain: "example.com").category).to eq("unknown")
  end

  it "falls back to domain evidence for unknown names" do
    result = classify("xyz123", domain: ".criteo.com")
    expect(result).to have_attributes(category: "marketing", provider: "Criteo", source: "builtin:domain")
  end

  it "combines independent weak signals of the same category" do
    # domain says performance (0.9); unrelated keywords don't apply
    expect(classify("abc", domain: "static.hotjar.com").category).to eq("performance")
    # two independent 0.6 keyword signals (A/B + analytics) => 0.84
    result = classify("ab_analytics")
    expect(result.category).to eq("performance")
    expect(result.confidence).to be_within(0.001).of(0.84)
  end

  it "marks cookies at or below the threshold as unknown and keeps the suggestion" do
    result = classify("user_lang")
    expect(result).to have_attributes(category: "unknown", suggested_category: "functionality", confidence: 0.6)
    expect(classify("zzz")).to have_attributes(category: "unknown", confidence: 0.0)
  end

  it "uses a strict threshold" do
    expect(described_class.new(threshold: 0.95).classify(cookie_record("_ga")).category).to eq("unknown")
    expect(described_class.new(threshold: 0.5).classify(cookie_record("user_lang")).category).to eq("functionality")
  end

  context "with custom rules" do
    let(:rules_file) do
      path = File.join(Dir.mktmpdir, "rules.yml")
      File.write(path, <<~YAML)
        cookies:
          - { name: _ga, category: marketing, confidence: 0.99, description: "Ads enabled GA" }
          - { name: "acme_*", category: functionality, confidence: 0.9, description: "ACME platform" }
        domains:
          - { domain: acme-ads.com, category: marketing, confidence: 0.9 }
      YAML
      path
    end

    subject(:classifier) { described_class.new(custom_rules_file: rules_file) }

    it "lets custom name rules override built-in ones" do
      expect(classify("_ga")).to have_attributes(category: "marketing", description: "Ads enabled GA",
                                                 source: "custom:name")
      expect(classify("acme_pref").category).to eq("functionality")
      expect(classify("x", domain: "t.acme-ads.com").category).to eq("marketing")
    end
  end

  it "rejects rules with invalid categories" do
    path = File.join(Dir.mktmpdir, "bad.yml")
    File.write(path, "cookies:\n  - { name: a, category: analytics }\n")
    expect { described_class.new(custom_rules_file: path) }.to raise_error(Cookiejar::Error, /invalid category/)
  end

  it "has a valid built-in knowledge base" do
    data = YAML.safe_load_file(described_class::BUILTIN_RULES)
    names = data["cookies"].map { |r| r["name"] }
    expect(names.uniq.size).to eq(names.size)
    expect(data.values.flatten.map { |r| r["confidence"] }).to all(be_between(0, 1))
  end
end
