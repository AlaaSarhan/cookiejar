# frozen_string_literal: true

require "json"

RSpec.describe Cookiejar::CookieRecord do
  let(:now) { Time.at(1_700_000_000) }

  describe "#storage_duration" do
    it "reports session cookies" do
      expect(cookie_record("a").storage_duration).to eq("Session")
    end

    it "reports the two most significant units of the remaining lifetime" do
      expect(cookie_record("a", expires: now.to_i + 400 * 86_400).storage_duration).to eq("1 year 1 month")
      expect(cookie_record("a", expires: now.to_i + 86_400 + 3_600).storage_duration).to eq("1 day 1 hour")
      expect(cookie_record("a", expires: now.to_i + 7_200).storage_duration).to eq("2 hours")
      expect(cookie_record("a", expires: now.to_i + 45).storage_duration).to eq("45 seconds")
    end

    it "rounds to the smallest unit shown, since cookies are observed a little after they were set" do
      expect(cookie_record("a", expires: now.to_i + 90 * 86_400 - 7).storage_duration).to eq("3 months")
      expect(cookie_record("a", expires: now.to_i + 365 * 86_400 - 90).storage_duration).to eq("1 year")
      expect(cookie_record("a", expires: now.to_i + 86_400 + 60).storage_duration).to eq("1 day")
      expect(cookie_record("a", expires: now.to_i + 2 * 3_600 - 20).storage_duration).to eq("2 hours")
    end

    it "reports already expired cookies" do
      expect(cookie_record("a", expires: now.to_i - 10).storage_duration).to eq("Expired")
    end
  end

  describe "#security_settings" do
    it "lists enabled flags and SameSite" do
      c = cookie_record("a", secure: true, httpOnly: true, sameSite: "Strict")
      expect(c.security_settings).to eq("Secure; HttpOnly; SameSite=Strict")
    end

    it "marks unset SameSite and partitioned cookies" do
      c = cookie_record("a", partitionKey: { "topLevelSite" => "https://example.com" })
      expect(c.security_settings).to eq("SameSite=Unset; Partitioned")
    end
  end

  describe "#first_party?" do
    it "compares registrable domains" do
      expect(cookie_record("a", domain: ".shop.example.com", site_url: "https://www.example.com/")).to be_first_party
      expect(cookie_record("a", domain: ".doubleclick.net")).not_to be_first_party
      expect(cookie_record("a", domain: "a.example.co.uk", site_url: "https://b.example.co.uk")).to be_first_party
      expect(cookie_record("a", domain: "other.co.uk", site_url: "https://example.co.uk")).not_to be_first_party
    end
  end

  describe "#details_json" do
    it "omits the value by default and records where the cookie was seen" do
      c = cookie_record("a", expires: now.to_i + 60)
      c.observe(raw_cookie("a", expires: now.to_i + 60), page_url: "https://example.com/next")
      details = JSON.parse(c.details_json)
      expect(details).not_to have_key("value")
      expect(details).to include("name" => "a", "party" => "first", "storageDuration" => "1 minute",
                                 "firstSeenOn" => "https://example.com/",
                                 "seenOn" => ["https://example.com/", "https://example.com/next"])
      expect(details["expiresAt"]).to eq(Time.at(now.to_i + 60).utc.iso8601)
    end

    it "includes the value when asked" do
      expect(JSON.parse(cookie_record("a").details_json(include_value: true))["value"]).to eq("secret")
    end
  end
end
