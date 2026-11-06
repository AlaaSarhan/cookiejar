# frozen_string_literal: true

RSpec.describe Cookiejar::Glob do
  it "matches literally without wildcards" do
    expect(described_class.match?("/about", "/about")).to be true
    expect(described_class.match?("/about", "/about/team")).to be false
  end

  it "treats * as any characters within a path segment" do
    expect(described_class.match?("/blog/*", "/blog/hello")).to be true
    expect(described_class.match?("/blog/*", "/blog/2024/hello")).to be false
    expect(described_class.match?("_ga_*", "_ga_ABC123")).to be true
  end

  it "treats ** as any characters across segments" do
    expect(described_class.match?("/blog/**", "/blog/2024/hello")).to be true
    expect(described_class.match?("**.pdf", "/files/a/b.pdf")).to be true
  end

  it "treats ? as a single character" do
    expect(described_class.match?("__utm?", "__utma")).to be true
    expect(described_class.match?("__utm?", "__utmzz")).to be false
  end

  it "escapes regexp metacharacters" do
    expect(described_class.match?("ASP.NET_SessionId", "ASPXNET_SessionId")).to be false
    expect(described_class.match?("/a+b(c)", "/a+b(c)")).to be true
  end
end
