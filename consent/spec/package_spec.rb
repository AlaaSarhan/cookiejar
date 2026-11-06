# frozen_string_literal: true

require "json"

# The banner is released to npm and as a gem from the same tag, so both must
# carry the same version.
RSpec.describe "npm package" do
  let(:package) { JSON.parse(File.read(File.expand_path("../package.json", __dir__))) }

  it "has the gem's version" do
    expect(package["version"]).to eq(CookiejarConsent::VERSION)
  end

  it "ships the banner script" do
    expect(package["files"]).to include(package["main"])
    expect(File).to exist(File.expand_path("../#{package["main"]}", __dir__))
  end
end
