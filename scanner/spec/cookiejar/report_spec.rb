# frozen_string_literal: true

require "csv"
require "json"

RSpec.describe Cookiejar::Report do
  let(:dir) { Dir.mktmpdir }
  let(:time) { Time.new(2026, 10, 5, 14, 30, 12) }

  def classified(*cookies)
    classifier = Cookiejar::Classifier.new
    cookies.each { |c| c.classification = classifier.classify(c) }
  end

  it "writes all cookies to one CSV file with their category" do
    cookies = classified(cookie_record("zzz"), cookie_record("_ga", expires: 1_700_000_000 + 86_400, secure: true,
                                                                    sameSite: "Lax"),
                         cookie_record("PHPSESSID", httpOnly: true))
    path = described_class.new(output_dir: dir, time: time).write(cookies)

    expect(path).to eq(File.join(dir, "cookies-20261005-143012.csv"))
    table = CSV.read(path, headers: true)
    expect(table.headers).to eq(described_class::HEADERS)
    expect(table.map { |r| [r["cookie name"], r["category"]] })
      .to eq([%w[PHPSESSID functionality], %w[_ga performance], %w[zzz unknown]])

    row = table[1]
    expect(row["cookie purpose/description"]).to eq("Google Analytics: distinguishes unique visitors.")
    expect(row["storage duration"]).to eq("1 day")
    expect(row["security settings"]).to eq("Secure; SameSite=Lax")
    expect(JSON.parse(row["full details"])).to include("domain" => "example.com",
                                                       "classification" => include("category" => "performance"))
  end

  it "never overwrites an earlier report" do
    first = described_class.new(output_dir: dir, time: time).write(classified(cookie_record("a")))
    second = described_class.new(output_dir: dir, time: time).write(classified(cookie_record("b")))
    later = described_class.new(output_dir: dir, time: time + 1).write([])

    expect(second).to eq(File.join(dir, "cookies-20261005-143012_2.csv"))
    expect(CSV.read(first, headers: true).map { |r| r["cookie name"] }).to eq(["a"])
    expect(described_class.files_in(dir)).to eq([first, second, later])
  end
end
