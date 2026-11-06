# frozen_string_literal: true

RSpec.describe Cookiejar::ReportDiff do
  let(:dir) { Dir.mktmpdir }

  def report(seconds, cookies, observed_at: Time.at(1_700_000_000))
    classifier = Cookiejar::Classifier.new
    records = cookies.map do |name, attrs|
      cookie_record(name, observed_at: observed_at, **attrs).tap { |c| c.classification = classifier.classify(c) }
    end
    Cookiejar::Report.new(output_dir: dir, time: Time.at(1_700_000_000 + seconds), include_values: true)
                        .write(records)
  end

  it "lists added, modified and removed cookies" do
    old = report(0, { "_ga" => { expires: 1_700_000_000 + (2 * 365 * 86_400) }, "PHPSESSID" => {},
                      "gone" => {}, "same" => { secure: true } })
    new = report(60, { "_ga" => { expires: 1_700_000_000 + 86_400 }, "PHPSESSID" => { httpOnly: true },
                       "same" => { secure: true }, "_fbp" => {}, "added" => { domain: ".shop.example.com" } })

    diff = described_class.new(old, new)
    expect(diff.added.map(&:to_s)).to eq(["_fbp (example.com)", "added (shop.example.com)"])
    expect(diff.removed.map(&:name)).to eq(["gone"])
    expect(diff.modified.to_h { |m| [m.cookie.name, m.fields] })
      .to eq("PHPSESSID" => ["security settings", "httpOnly"], "_ga" => ["storage duration"])
    expect(diff.to_s).to include("Added (2):\n  _fbp (example.com)\n  added (shop.example.com)",
                                 "Modified (2):\n  _ga (example.com): storage duration\n  PHPSESSID (example.com): security settings, httpOnly",
                                 "Removed (1):\n  gone (example.com)")
  end

  it "ignores values, sizes, absolute expiry and visited pages, which change on every scan" do
    old = report(0, { "_ga" => { expires: 1_700_000_000 + 86_400, value: "a", size: 5 } })
    new = report(60, { "_ga" => { expires: 1_700_000_060 + 86_400, value: "bb", size: 6 } },
                 observed_at: Time.at(1_700_000_060))
    expect(described_class.new(old, new).changes?).to be false
    expect(described_class.new(old, new).to_s).to include("Added (0):\n  none")
  end

  it "tells cookies with the same name on different domains apart" do
    old = report(0, { "id" => { domain: "a.com" } })
    new = report(60, { "id" => { domain: "b.com" } })
    diff = described_class.new(old, new)
    expect([diff.added.map(&:to_s), diff.removed.map(&:to_s)]).to eq([["id (b.com)"], ["id (a.com)"]])
  end

  it "compares the two newest reports in a directory" do
    report(0, { "a" => {} })
    old = report(60, { "b" => {} })
    new = report(120, { "c" => {} })
    diff = described_class.latest(dir)
    expect([diff.old_path, diff.new_path]).to eq([old, new])
  end

  it "rejects directories without two reports and files that are not reports" do
    report(0, {})
    expect { described_class.latest(dir) }.to raise_error(Cookiejar::Error, /need two reports.*found 1/)
    other = File.join(dir, "other.csv")
    File.write(other, "name,value\n")
    expect { described_class.new(other, other) }.to raise_error(Cookiejar::Error, /not a cookie report/)
  end
end
