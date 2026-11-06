# frozen_string_literal: true

module Cookiejar
  # Minimal wildcard matcher used by link filters.
  #
  #   *   matches any characters except "/"
  #   **  matches any characters, including "/"
  #   ?   matches a single character except "/"
  #
  # Patterns are anchored: they must match the whole subject.
  module Glob
    module_function

    def to_regexp(pattern)
      source = +""
      scanner = pattern.chars
      i = 0
      while i < scanner.length
        char = scanner[i]
        if char == "*" && scanner[i + 1] == "*"
          source << ".*"
          i += 2
          next
        end

        source << case char
                  when "*" then "[^/]*"
                  when "?" then "[^/]"
                  else Regexp.escape(char)
                  end
        i += 1
      end
      Regexp.new("\\A#{source}\\z")
    end

    def match?(pattern, subject)
      to_regexp(pattern).match?(subject)
    end
  end
end
