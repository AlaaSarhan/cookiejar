# frozen_string_literal: true

require "stringio"
require "json"

RSpec.describe CookiejarConsent::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:cli) { described_class.new(out: out, err: err) }

  it "builds the banner from the newest report" do
    dir = Dir.mktmpdir
    File.write(File.join(dir, "cookies-20231101-000000.csv"), "#{CookiejarConsent::REPORT_HEADERS.join(",")}\n")
    newest = copy_report(dir)

    expect(cli.run(["-r", dir, "--format", "json"])).to eq(0)
    expect(JSON.parse(out.string)["cookies"]["marketing"].map { |c| c["name"] }).to eq(%w[_fbp IDE])

    options = File.join(dir, "banner.yml")
    File.write(options, "revision: 7\n")
    script = File.join(dir, "consent.js")
    expect(cli.run([newest, "-w", script, "--options", options])).to eq(0)
    expect(File.read(script)).to include("window.CookiejarConsent", '"revision":7', '"_fbp"')
    expect(err.string).to include("Banner script for #{newest}: #{script}")

    json = File.join(dir, "cookies.json")
    expect(cli.run([newest, "-w", json])).to eq(0)
    expect(JSON.parse(File.read(json))).to have_key("cookies")
  end

  it "fails without a report or with invalid options" do
    expect(cli.run(["-r", Dir.mktmpdir])).to eq(2)
    expect(err.string).to include("no reports in")
    expect(cli.run(%w[--unknown functionality])).to eq(2)
  end

  it "prints help and version" do
    expect(cli.run(["--help"])).to eq(0)
    expect(cli.run(["--version"])).to eq(0)
    expect(out.string).to include("Usage: cookiejar-consent").and include(CookiejarConsent::VERSION)
  end
end
