# frozen_string_literal: true

require "csv"
require "json"

module Cookiejar
  # Compares two report files (see {Report}) and lists the cookies that were
  # added, removed or modified between them.
  #
  # Cookies are identified by name, domain and path. A cookie is modified when
  # any of its columns or full details differ, except for values that change on
  # every visit (cookie value and size, absolute expiry time) or depend on which
  # pages a scan visited.
  class ReportDiff
    COLUMNS = Report::HEADERS - ["cookie name", "full details"]
    # Details that change between scans without the cookie changing, or that
    # duplicate a column.
    IGNORED_DETAILS = %w[value size expires expiresAt firstSeenOn seenOn storageDuration classification.category
                         classification.description].freeze

    Cookie = Struct.new(:name, :domain, :path, :fields, keyword_init: true) do
      def key = [name, domain, path]
      def to_s = "#{name} (#{domain}#{path unless path == "/"})"
    end
    Modification = Struct.new(:cookie, :fields, keyword_init: true)

    attr_reader :old_path, :new_path

    # The two newest reports in a directory.
    def self.latest(dir)
      files = Report.files_in(dir)
      raise Error, "need two reports in #{dir} to compare, found #{files.size}" if files.size < 2

      new(*files.last(2))
    end

    def initialize(old_path, new_path)
      @old_path = old_path
      @new_path = new_path
      @old = load(old_path)
      @new = load(new_path)
    end

    def added = sorted(@new.values_at(*(@new.keys - @old.keys)))
    def removed = sorted(@old.values_at(*(@old.keys - @new.keys)))

    def modified
      (@old.keys & @new.keys).filter_map do |key|
        old_fields = @old[key].fields
        new_fields = @new[key].fields
        changed = (old_fields.keys | new_fields.keys).reject { |f| old_fields[f] == new_fields[f] }
        Modification.new(cookie: @new[key], fields: changed) if changed.any?
      end.sort_by { |m| sort_key(m.cookie) }
    end

    def changes? = [added, removed, modified].any?(&:any?)

    def to_s
      lines = ["Comparing #{@old_path}", "     with #{@new_path}", ""]
      section = lambda do |title, items|
        lines << "#{title} (#{items.size}):"
        lines.concat(items.empty? ? ["  none"] : items.map { |item| "  #{item}" })
        lines << ""
      end
      section.call("Added", added)
      section.call("Modified", modified.map { |m| "#{m.cookie}: #{m.fields.join(", ")}" })
      section.call("Removed", removed)
      lines.join("\n")
    end

    private

    def load(path)
      table = CSV.read(path, headers: true)
      missing = Report::HEADERS - table.headers
      raise Error, "#{path} is not a cookie report (missing columns: #{missing.join(", ")})" if missing.any?

      table.to_h do |row|
        details = JSON.parse(row["full details"].to_s)
        cookie = Cookie.new(
          name: row["cookie name"],
          domain: details["domain"].to_s.downcase.delete_prefix("."),
          path: details["path"].to_s,
          fields: COLUMNS.to_h { |c| [c, row[c]] }.merge(flatten(details).except(*IGNORED_DETAILS))
        )
        [cookie.key, cookie]
      end
    rescue Errno::ENOENT
      raise Error, "report not found: #{path}"
    rescue JSON::ParserError, CSV::MalformedCSVError => e
      raise Error, "cannot read report #{path}: #{e.message}"
    end

    def flatten(hash, prefix = nil)
      hash.each_with_object({}) do |(key, value), flat|
        name = prefix ? "#{prefix}.#{key}" : key
        value.is_a?(Hash) ? flat.merge!(flatten(value, name)) : flat[name] = value
      end
    end

    def sorted(cookies) = cookies.sort_by { |c| sort_key(c) }
    def sort_key(cookie) = [cookie.name.downcase, cookie.domain, cookie.path]
  end
end
