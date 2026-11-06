# frozen_string_literal: true

require "json"
require "csv"

RSpec.describe ConsentLog::App do
  let(:dir) { Dir.mktmpdir }
  let(:store) { ConsentLog::Store.new(dir) }
  let(:rate_limit) { 60 }
  let(:app) do
    described_class.new(store: store, allowed_origins: ["https://example.com"], admin_token: "s3cret",
                        rate_limit: rate_limit)
  end
  let(:record) do
    {
      "id" => "0b6d8f1e-1c2d-4e5f-9a8b-7c6d5e4f3a2b", "timestamp" => "2026-11-06T10:00:00.000Z",
      "action" => "custom",
      "categories" => { "functionality" => true, "performance" => true, "marketing" => false, "unknown" => false },
      "revision" => "2", "report" => "cookies-20261105-120000.csv", "fingerprint" => "a1b2c3d4e5f6a7b8",
      "url" => "https://example.com/pricing", "language" => "de", "bannerVersion" => "1"
    }
  end

  after { store.close }

  def post_record(data = record, origin: "https://example.com")
    body = data.is_a?(String) ? data : JSON.generate(data)
    post "/consents", body, { "CONTENT_TYPE" => "text/plain;charset=UTF-8", "HTTP_ORIGIN" => origin }.compact
  end

  def admin_get(path, **params)
    get path, params, { "HTTP_AUTHORIZATION" => "Bearer s3cret" }
  end

  it "stores records from allowed origins" do
    post_record
    expect(last_response.status).to eq(204)
    expect(last_response.headers["access-control-allow-origin"]).to eq("https://example.com")

    admin_get("/consents/#{record["id"]}")
    expect(last_response.status).to eq(200)
    stored = JSON.parse(last_response.body)
    expect(stored.size).to eq(1)
    expect(stored.first).to include(
      "consent_id" => record["id"], "action" => "custom", "client_time" => "2026-11-06T10:00:00.000Z",
      "functionality" => true, "performance" => true, "marketing" => false, "unknown" => false,
      "revision" => "2", "report" => "cookies-20261105-120000.csv", "fingerprint" => "a1b2c3d4e5f6a7b8",
      "url" => "https://example.com/pricing", "language" => "de", "banner_version" => "1"
    )
    expect(Time.iso8601(stored.first["received_at"])).to be_within(5).of(Time.now)
  end

  it "keeps the history of a visitor's decisions" do
    post_record
    post_record(record.merge("action" => "reject_all", "categories" => { "functionality" => true }))
    admin_get("/consents/#{record["id"]}")
    expect(JSON.parse(last_response.body).map { |r| [r["action"], r["performance"]] })
      .to eq([["custom", true], ["reject_all", false]])
  end

  it "rejects other origins" do
    post_record(origin: "https://evil.example")
    expect(last_response.status).to eq(403)
    post_record(origin: nil)
    expect(last_response.status).to eq(403)
  end

  it "takes the origin from the Referer when the browser sends no Origin" do
    post "/consents", JSON.generate(record), { "HTTP_REFERER" => "https://example.com/pricing?x=1" }
    expect(last_response.status).to eq(204)
    post "/consents", JSON.generate(record), { "HTTP_REFERER" => "https://example.com.evil.example/" }
    expect(last_response.status).to eq(403)
    post "/consents", JSON.generate(record), { "HTTP_REFERER" => "http://example.com/" }
    expect(last_response.status).to eq(403)
  end

  it "accepts any origin when configured with *" do
    open_app = described_class.new(store: store, allowed_origins: ["*"])
    status, = open_app.call(Rack::MockRequest.env_for("/consents", method: "POST", input: JSON.generate(record)))
    expect(status).to eq(204)
  end

  it "rejects invalid records" do
    invalid = {
      "not json" => "nope",
      "array" => "[]",
      "bad id" => record.merge("id" => "x"),
      "bad action" => record.merge("action" => "maybe"),
      "unknown category" => record.merge("categories" => { "functionality" => true, "spying" => true }),
      "non-boolean category" => record.merge("categories" => { "functionality" => true, "marketing" => "yes" }),
      "functionality denied" => record.merge("categories" => { "functionality" => false }),
      "bad url" => record.merge("url" => "javascript:alert(1)"),
      "long field" => record.merge("report" => "x" * 200),
      "bad timestamp" => record.merge("timestamp" => "yesterday")
    }
    statuses = invalid.transform_values do |data|
      post_record(data)
      last_response.status
    end
    expect(statuses).to eq(invalid.transform_values { |data| data.is_a?(String) ? 400 : 422 }.merge("array" => 422))
    admin_get("/consents")
    expect(last_response.body).to be_empty
  end

  it "rejects oversized bodies" do
    post_record(record.merge("padding" => "x" * 10_000))
    expect(last_response.status).to eq(413)
  end

  context "with a rate limit" do
    let(:rate_limit) { 2 }

    it "limits records per client IP" do
      3.times { post_record }
      expect(last_response.status).to eq(429)
    end
  end

  it "answers CORS preflights for allowed origins" do
    options "/consents", nil, { "HTTP_ORIGIN" => "https://example.com" }
    expect(last_response.status).to eq(204)
    expect(last_response.headers["access-control-allow-methods"]).to eq("POST")
  end

  it "exports records as JSON lines or CSV, filtered by time" do
    post_record
    post_record(record.merge("id" => "another-visitor-1"))

    admin_get("/consents")
    expect(last_response.body.lines.map { |l| JSON.parse(l)["consent_id"] })
      .to eq([record["id"], "another-visitor-1"])

    admin_get("/consents", format: "csv")
    csv = CSV.parse(last_response.body, headers: true)
    expect(csv.headers).to eq(ConsentLog::Store::COLUMNS)
    expect(csv.map { |r| r["consent_id"] }).to eq([record["id"], "another-visitor-1"])

    admin_get("/consents", from: (Time.now + 60).iso8601)
    expect(last_response.body).to be_empty
    admin_get("/consents", from: "garbage")
    expect(last_response.status).to eq(400)
  end

  it "requires the admin token to read records" do
    post_record
    get "/consents/#{record["id"]}"
    expect(last_response.status).to eq(401)
    get "/consents/#{record["id"]}", {}, { "HTTP_AUTHORIZATION" => "Bearer wrong" }
    expect(last_response.status).to eq(401)
  end

  it "disables reading without an admin token" do
    no_admin = described_class.new(store: store, allowed_origins: ["https://example.com"])
    status, = no_admin.call(Rack::MockRequest.env_for("/consents/#{record["id"]}", "HTTP_AUTHORIZATION" => "Bearer "))
    expect(status).to eq(404)
  end

  it "reports health" do
    get "/health"
    expect(last_response.status).to eq(200)
  end

  it "refuses to start without allowed origins" do
    expect { described_class.new(store: store, allowed_origins: []) }.to raise_error(ConsentLog::Error)
  end
end

RSpec.describe ConsentLog::Store do
  let(:dir) { Dir.mktmpdir }
  let(:store) { described_class.new(dir) }
  let(:day) { Time.utc(2026, 11, 6, 12) }

  def record(id = "abcdefgh-1234", action: "accept_all")
    ConsentLog::Record.from("id" => id, "action" => action,
                            "categories" => ConsentLog::CATEGORIES.to_h { |c| [c, true] })
  end

  it "appends records as JSON lines to one file per day of receipt" do
    store.insert(record, received_at: day)
    store.insert(record("other-visitor"), received_at: day + 3600)
    store.insert(record(action: "reject_all"), received_at: day + 86_400)

    expect(Dir.children(dir).sort).to eq(%w[consents-2026-11-06.jsonl consents-2026-11-07.jsonl])
    lines = File.readlines(File.join(dir, "consents-2026-11-06.jsonl")).map { |l| JSON.parse(l) }
    expect(lines.first).to eq(
      "consent_id" => "abcdefgh-1234", "received_at" => "2026-11-06T12:00:00.000Z", "client_time" => nil,
      "action" => "accept_all", "functionality" => true, "performance" => true, "marketing" => true,
      "unknown" => true, "revision" => nil, "report" => nil, "fingerprint" => nil, "url" => nil,
      "language" => nil, "banner_version" => nil
    )
    expect(lines.first.keys).to eq(described_class::COLUMNS)
    expect(store.history("abcdefgh-1234").map { |r| r["action"] }).to eq(%w[accept_all reject_all])
  end

  it "reads the records of earlier runs and selects them by time" do
    store.insert(record, received_at: day)
    store.insert(record, received_at: day + 86_400)
    reopened = described_class.new(dir)

    rows = []
    reopened.each_between(from: day + 1, to: day + 86_401) { |row| rows << row["received_at"] }
    expect(rows).to eq(["2026-11-07T12:00:00.000Z"])
  end

  it "skips a record a crash left half written and keeps later records intact" do
    path = File.join(dir, "consents-2026-11-06.jsonl")
    File.write(path, %({"consent_id":"abcdefgh-1234","received_at":"2026-11-06T10:00:00.000Z"}\n{"consent_id":"abcdefgh-1234","rec))
    logger = instance_double(Logger, warn: nil)
    store = described_class.new(dir, logger: logger)
    store.insert(record, received_at: day)

    expect(store.history("abcdefgh-1234").map { |r| r["received_at"] })
      .to eq(%w[2026-11-06T10:00:00.000Z 2026-11-06T12:00:00.000Z])
    expect(logger).to have_received(:warn).with(/skipping damaged record/)
  end

  it "purges whole days that ended before the time" do
    store.insert(record, received_at: day - (2 * 86_400))
    store.insert(record, received_at: day - 86_400)
    store.insert(record, received_at: day - 86_400 + 60)
    store.insert(record, received_at: day)

    expect(store.purge(before: day)).to eq(3)
    expect(Dir.children(dir)).to eq(["consents-2026-11-06.jsonl"])
    expect(store.history("abcdefgh-1234").size).to eq(1)
  end

  it "refuses a missing data directory" do
    expect { described_class.new(File.join(dir, "nope")) }.to raise_error(ConsentLog::Error, /does not exist/)
  end
end
