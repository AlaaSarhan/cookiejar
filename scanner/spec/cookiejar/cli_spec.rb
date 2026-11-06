# frozen_string_literal: true

require "stringio"
require "json"

RSpec.describe Cookiejar::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:cli) { described_class.new(out: out, err: err) }

  it "parses start URIs and options" do
    config = cli.parse(%w[https://a.com https://b.com --no-follow-links -d 3 --max-pages 7
                          --allow-domain a.com,cdn.a.com --allow-domain b.com
                          --include-path /blog/** --exclude-path /admin/** --include-href /x --exclude-href **.pdf
                          -o out --threshold 0.9 --include-values --browser-path /bin/chrome --settle 2.5
                          --max-settle 20])
    expect(config).to have_attributes(
      start_uris: %w[https://a.com https://b.com], follow_links: false, depth: 3, max_pages: 7,
      allowed_domains: %w[a.com cdn.a.com b.com], include_paths: ["/blog/**"], exclude_paths: ["/admin/**"],
      include_hrefs: ["/x"], exclude_hrefs: ["**.pdf"], output_dir: "out", confidence_threshold: 0.9,
      include_values: true, browser_path: "/bin/chrome", settle_time: 2.5, max_settle_time: 20
    )
  end

  it "merges a YAML config file, with CLI options taking precedence" do
    path = File.join(Dir.mktmpdir, "scan.yml")
    File.write(path, <<~YAML)
      start_uris: [https://a.com]
      depth: 4
      exclude_paths: ["/admin/**"]
    YAML
    config = cli.parse(["-c", path, "-d", "2", "--exclude-path", "/tmp/*", "https://b.com"])
    expect(config).to have_attributes(start_uris: %w[https://a.com https://b.com], depth: 2,
                                      exclude_paths: ["/admin/**", "/tmp/*"])
  end

  it "rejects unknown config keys" do
    path = File.join(Dir.mktmpdir, "scan.yml")
    File.write(path, "nope: 1\n")
    expect(cli.run(["-c", path, "https://a.com"])).to eq(2)
    expect(err.string).to include("unknown config option: nope")
  end

  it "fails with usage on invalid input" do
    expect(cli.run([])).to eq(2)
    expect(cli.run(["ftp://a.com"])).to eq(2)
    expect(cli.run(["--depth", "x", "https://a.com"])).to eq(2)
    expect(err.string).to include("start URI must be http(s)")
  end

  it "rejects a max settle time below the settle time" do
    expect(cli.run(["--settle", "5", "--max-settle", "3", "https://a.com"])).to eq(2)
    expect(err.string).to include("max_settle_time must be >= settle_time")
  end

  it "compares two reports" do
    dir = Dir.mktmpdir
    write = lambda do |seconds, names|
      cookies = names.map { |n| cookie_record(n).tap { |c| c.classification = Cookiejar::Classifier.new.classify(c) } }
      Cookiejar::Report.new(output_dir: dir, time: Time.at(1_700_000_000 + seconds)).write(cookies)
    end
    old = write.call(0, %w[a b])
    new = write.call(60, %w[b c])

    expect(cli.run(["diff", "-o", dir])).to eq(0)
    expect(out.string).to include("Added (1):\n  c (example.com)", "Removed (1):\n  a (example.com)")
    expect(cli.run(["diff", new, old])).to eq(0)
    expect(out.string).to include("Comparing #{new}")
    expect(cli.run(["diff", old])).to eq(2)
    expect(err.string).to include("diff takes two report files")
  end

  it "prints help and version" do
    expect(cli.run(["--help"])).to eq(0)
    expect(cli.run(["--version"])).to eq(0)
    expect(out.string).to include("Usage: cookiejar").and include(Cookiejar::VERSION)
  end
end
