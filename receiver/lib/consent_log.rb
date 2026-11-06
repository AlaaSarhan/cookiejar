# frozen_string_literal: true

require "csv"
require "json"
require "time"
require "uri"
require "rack"
require "date"

# Stores the consent records sent by the cookiejar consent banner, so a site
# can prove which visitor consented to what, and when.
module ConsentLog
  class Error < StandardError; end

  VERSION = "0.1.0"

  CATEGORIES = %w[functionality performance marketing unknown].freeze
  ACTIONS = %w[accept_all reject_all custom api].freeze

  # A validated consent record from the banner.
  class Record
    ID = /\A[A-Za-z0-9-]{8,64}\z/
    LIMITS = { "revision" => 64, "report" => 128, "fingerprint" => 64, "url" => 2048, "language" => 16,
               "bannerVersion" => 16 }.freeze

    class Invalid < Error; end

    attr_reader :attributes

    # @param data [Hash] the parsed JSON body
    def self.from(data)
      raise Invalid, "record must be a JSON object" unless data.is_a?(Hash)

      new(data)
    end

    def initialize(data)
      @attributes = {
        "consent_id" => id(data["id"]),
        "client_time" => client_time(data["timestamp"]),
        "action" => action(data["action"])
      }.merge(categories(data["categories"]))
      LIMITS.each { |key, max| @attributes[column(key)] = optional_string(data, key, max) }
      url = @attributes["url"]
      raise Invalid, "url must be http(s)" if url && !url.match?(%r{\Ahttps?://}i)
    end

    private

    def id(value)
      raise Invalid, "id is missing or invalid" unless value.is_a?(String) && value.match?(ID)

      value
    end

    def client_time(value)
      return nil if value.nil?
      raise Invalid, "timestamp must be an ISO 8601 time" unless value.is_a?(String) && value.size <= 40

      Time.iso8601(value).utc.iso8601(3)
    rescue ArgumentError
      raise Invalid, "timestamp must be an ISO 8601 time"
    end

    def action(value)
      raise Invalid, "action must be one of #{ACTIONS.join(", ")}" unless ACTIONS.include?(value)

      value
    end

    def categories(value)
      raise Invalid, "categories must be an object" unless value.is_a?(Hash)

      unknown = value.keys - CATEGORIES
      raise Invalid, "unknown categories: #{unknown.join(", ")}" if unknown.any?

      CATEGORIES.to_h do |category|
        choice = value.fetch(category, false)
        raise Invalid, "category #{category} must be true or false" unless [true, false].include?(choice)

        [category, choice ? 1 : 0]
      end.tap { |c| raise Invalid, "functionality is always granted" unless c["functionality"] == 1 }
    end

    def optional_string(data, key, max)
      value = data[key]
      return nil if value.nil?
      raise Invalid, "#{key} must be a string of at most #{max} characters" unless value.is_a?(String) && value.size <= max

      value
    end

    def column(key) = key.gsub(/([A-Z])/) { "_#{::Regexp.last_match(1).downcase}" }
  end

  # Append-only storage of consent records in JSON Lines files, one per day
  # (UTC) of receipt: consents-2026-11-06.jsonl. A day's file never changes once
  # the day is over, so it can be archived to write-once storage, and records
  # are purged by deleting whole files.
  class Store
    COLUMNS = %w[consent_id received_at client_time action functionality performance marketing unknown
                 revision report fingerprint url language banner_version].freeze
    FILE = /\Aconsents-(\d{4}-\d{2}-\d{2})\.jsonl\z/

    def initialize(dir, logger: nil)
      raise Error, "data directory #{dir} does not exist" unless File.directory?(dir)

      @dir = dir
      @logger = logger
      @mutex = Mutex.new
      @checked = {}
    end

    def insert(record, received_at: Time.now)
      received_at = received_at.utc
      row = { "consent_id" => nil, "received_at" => received_at.iso8601(3) }.merge(record.attributes)
      CATEGORIES.each { |category| row[category] = row[category] == 1 }
      line = "#{JSON.generate(row.slice(*COLUMNS))}\n"
      path = path_for(received_at.to_date)
      @mutex.synchronize do
        File.open(path, File::WRONLY | File::APPEND | File::CREAT, 0o640) do |file|
          file.write(terminate_partial_line(path, file) + line)
          # Answer only once the record is on disk.
          file.fsync
        end
      end
      nil
    end

    # All records of one consent ID, oldest first.
    def history(consent_id)
      needle = JSON.generate(consent_id)
      records = []
      files.each do |_date, path|
        each_line(path) do |line|
          next unless line.include?(needle)

          row = parse(line, path)
          records << row if row && row["consent_id"] == consent_id
        end
      end
      records
    end

    # Records received in [from, to), oldest first.
    def each_between(from: nil, to: nil)
      from_s = from&.utc&.iso8601(3)
      to_s = to&.utc&.iso8601(3)
      files.each do |date, path|
        next if from && date < from.utc.to_date
        next if to && date > to.utc.to_date

        each_line(path) do |line|
          row = parse(line, path) or next
          next if from_s && row["received_at"] < from_s
          next if to_s && row["received_at"] >= to_s

          yield row
        end
      end
    end

    # Deletes the files of days that ended before the time, so only whole days
    # are purged.
    # @return [Integer] number of deleted records
    def purge(before:)
      cutoff = before.utc.to_date
      @mutex.synchronize do
        files.sum do |date, path|
          next 0 unless date < cutoff

          count = File.foreach(path).count
          File.delete(path)
          @checked.delete(path)
          count
        end
      end
    end

    def healthy? = File.directory?(@dir) && File.writable?(@dir)

    def close; end

    private

    def path_for(date) = File.join(@dir, "consents-#{date.iso8601}.jsonl")

    def files
      Dir.children(@dir).filter_map do |name|
        match = FILE.match(name) or next
        [Date.iso8601(match[1]), File.join(@dir, name)]
      end.sort
    end

    # A crash can leave a partial last line; start the next record on a line of its own.
    def terminate_partial_line(path, file)
      return "" if @checked[path]

      @checked[path] = true
      return "" if file.size.zero?

      File.open(path, "rb") do |f|
        f.seek(-1, IO::SEEK_END)
        f.read(1) == "\n" ? "" : "\n"
      end
    end

    def each_line(path, &)
      File.foreach(path, chomp: true, &)
    rescue Errno::ENOENT
      nil # purged meanwhile
    end

    def parse(line, path)
      return nil if line.empty?

      JSON.parse(line)
    rescue JSON::ParserError
      @logger&.warn("skipping damaged record in #{path}: #{line[0, 80]}")
      nil
    end
  end

  # Fixed-window request limit per client IP, kept in memory.
  class RateLimiter
    def initialize(per_minute)
      @limit = per_minute
      @counts = Hash.new(0)
      @window = nil
      @mutex = Mutex.new
    end

    def allow?(key)
      return true unless @limit.positive?

      @mutex.synchronize do
        window = Time.now.to_i / 60
        @counts.clear unless window == @window
        @window = window
        (@counts[key] += 1) <= @limit
      end
    end
  end

  # The HTTP API:
  #   POST /consents            store a record (from the banner)
  #   GET  /consents/:id        all records of a consent ID      (admin token)
  #   GET  /consents?from=&to=  export as JSON lines or CSV      (admin token)
  #   GET  /health
  class App
    MAX_BODY = 8 * 1024

    # @param allowed_origins [Array<String>] origins allowed to post records; "*" for any
    # @param admin_token [String, nil] bearer token for reading records; reading is disabled without one
    def initialize(store:, allowed_origins:, admin_token: nil, rate_limit: 60, logger: nil)
      raise Error, "no allowed origins configured" if allowed_origins.empty?

      @store = store
      @allowed_origins = allowed_origins.map { |o| o.chomp("/").downcase }
      @admin_token = admin_token.to_s.empty? ? nil : admin_token
      @limiter = RateLimiter.new(rate_limit)
      @logger = logger
    end

    def call(env)
      request = Rack::Request.new(env)
      case [request.request_method, request.path_info]
      in ["POST", "/consents"] then create(request)
      in ["OPTIONS", "/consents"] then preflight(request)
      in ["GET", "/consents"] then export(request)
      in ["GET", %r{\A/consents/[^/]+\z} => path] then show(request, path.delete_prefix("/consents/"))
      in ["GET" | "HEAD", "/health"] then health
      else respond(404, "not found")
      end
    rescue StandardError => e
      @logger&.error("#{e.class}: #{e.message}")
      respond(500, "internal error")
    end

    private

    def create(request)
      origin = origin_of(request)
      return respond(403, "origin not allowed") unless allowed_origin?(origin)
      return respond(429, "too many requests") unless @limiter.allow?(request.ip)

      body = request.body&.read(MAX_BODY + 1).to_s
      return respond(413, "record too large", cors: origin) if body.bytesize > MAX_BODY

      record = Record.from(JSON.parse(body))
      @store.insert(record)
      [204, cors_headers(origin), []]
    rescue JSON::ParserError
      respond(400, "body must be JSON", cors: origin)
    rescue Record::Invalid => e
      respond(422, e.message, cors: origin)
    end

    def preflight(request)
      origin = origin_of(request)
      return respond(403, "origin not allowed") unless allowed_origin?(origin)

      [204, cors_headers(origin).merge("access-control-allow-methods" => "POST",
                                       "access-control-allow-headers" => "content-type",
                                       "access-control-max-age" => "86400"), []]
    end

    def show(request, consent_id)
      return unauthorized unless admin?(request)

      # Rack paths are binary strings.
      consent_id = Rack::Utils.unescape_path(consent_id).dup.force_encoding(Encoding::UTF_8)
      return respond(400, "invalid consent ID") unless consent_id.valid_encoding? && consent_id.match?(Record::ID)

      json(200, @store.history(consent_id))
    end

    def export(request)
      return unauthorized unless admin?(request)

      from = time_param(request, "from")
      to = time_param(request, "to")
      format = request.params["format"] || "jsonl"
      return respond(400, "format must be jsonl or csv") unless %w[jsonl csv].include?(format)

      body = Enumerator.new do |out|
        out << CSV.generate_line(Store::COLUMNS) if format == "csv"
        @store.each_between(from: from, to: to) do |row|
          out << (format == "csv" ? CSV.generate_line(row.values) : "#{JSON.generate(row)}\n")
        end
      end
      type = format == "csv" ? "text/csv" : "application/x-ndjson"
      [200, { "content-type" => "#{type}; charset=utf-8", "cache-control" => "no-store" }, body]
    rescue ArgumentError
      respond(400, "from and to must be ISO 8601 times")
    end

    def health
      @store.healthy? ? respond(200, "ok") : respond(503, "data directory not writable")
    end

    # Browsers leave out the Origin header of beacons to other origins on the
    # same site (e.g. from www.example.com to consent.example.com), but send a
    # Referer, which holds at least the origin unless the page disables it.
    def origin_of(request)
      origin = request.get_header("HTTP_ORIGIN")
      return origin if origin && origin != "null"

      uri = URI.parse(request.get_header("HTTP_REFERER").to_s)
      uri.host && uri.scheme ? "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}" : nil
    rescue URI::InvalidURIError
      nil
    end

    def allowed_origin?(origin)
      return true if @allowed_origins.include?("*")

      !origin.nil? && @allowed_origins.include?(origin.downcase)
    end

    def cors_headers(origin)
      origin ? { "access-control-allow-origin" => origin, "vary" => "origin" } : {}
    end

    def admin?(request)
      return false unless @admin_token

      token = request.get_header("HTTP_AUTHORIZATION").to_s[/\ABearer (.+)\z/, 1]
      !token.nil? && Rack::Utils.secure_compare(token, @admin_token)
    end

    def unauthorized
      return respond(404, "not found") unless @admin_token

      [401, { "content-type" => "text/plain", "www-authenticate" => "Bearer" }, ["unauthorized\n"]]
    end

    def time_param(request, name)
      value = request.params[name]
      value.nil? || value.empty? ? nil : Time.iso8601(value)
    end

    def json(status, data)
      [status, { "content-type" => "application/json", "cache-control" => "no-store" }, [JSON.generate(data)]]
    end

    def respond(status, message, cors: nil)
      [status, { "content-type" => "text/plain" }.merge(cors ? cors_headers(cors) : {}), ["#{message}\n"]]
    end
  end

  # Settings from the environment, shared by config.ru and bin/consent-log.
  module Settings
    module_function

    def data_dir = ENV.fetch("DATA_DIR", File.expand_path("../data", __dir__))
    def allowed_origins = ENV.fetch("ALLOWED_ORIGINS", "").split(",").map(&:strip).reject(&:empty?)
    def admin_token = ENV.fetch("ADMIN_TOKEN", nil)
    def rate_limit = Integer(ENV.fetch("RATE_LIMIT", "60"))
  end
end
