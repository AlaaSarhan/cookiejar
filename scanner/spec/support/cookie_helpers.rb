# frozen_string_literal: true

module CookieHelpers
  def raw_cookie(name, domain: "example.com", path: "/", expires: -1, **extra)
    {
      "name" => name, "value" => "secret", "domain" => domain, "path" => path,
      "expires" => expires, "size" => name.size + 6, "httpOnly" => false, "secure" => false,
      "session" => expires.to_f <= 0
    }.merge(extra.transform_keys(&:to_s))
  end

  def cookie_record(name, site_url: "https://example.com/", observed_at: Time.at(1_700_000_000), **attrs)
    Cookiejar::CookieRecord.new(raw_cookie(name, **attrs), page_url: site_url, site_url: site_url,
                                                              observed_at: observed_at)
  end
end

RSpec.configure { |c| c.include CookieHelpers }

module ReportHelpers
  # Writes a classified report of cookie records to dir and returns its path.
  def write_report(dir, cookies, time: Time.at(1_700_000_000))
    classifier = Cookiejar::Classifier.new
    cookies.each { |c| c.classification = classifier.classify(c) }
    Cookiejar::Report.new(output_dir: dir, time: time).write(cookies)
  end
end

RSpec.configure { |c| c.include ReportHelpers }
