# syntax=docker/dockerfile:1

# Chrome for Testing has no Linux ARM build, so the image uses Debian's Chromium,
# which works on both amd64 and arm64 (e.g. Apple Silicon).
ARG RUBY_VERSION=4.0

# Gems with native extensions (websocket-driver) need a compiler, kept out of the final image.
FROM ruby:${RUBY_VERSION}-slim AS gems

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test

COPY Gemfile Gemfile.lock cookiejar.gemspec ./
COPY lib/cookiejar/version.rb lib/cookiejar/

RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache

FROM ruby:${RUBY_VERSION}-slim

LABEL org.opencontainers.image.title="cookiejar-scanner" \
      org.opencontainers.image.description="Scans websites for cookies in headless Chromium and writes categorised CSV reports" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium fonts-liberation fonts-noto-color-emoji \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY . .

RUN useradd --create-home --uid 1000 cookiejar \
 && mkdir /reports && chown cookiejar /reports

USER cookiejar

# Chromium's sandbox needs privileges containers don't have by default;
# FERRUM_CHROME_DOCKERIZE makes Ferrum start it with --no-sandbox.
ENV BROWSER_PATH=/usr/bin/chromium \
    FERRUM_CHROME_DOCKERIZE=true

# The Open Cookie Database isn't part of the image; mount a directory with it here.
# Without it, cookies are classified by the built-in rules only.
ENV COOKIE_DATABASE=/cookie-database/open-cookie-database.csv

# Reports are written relative to the working directory (cookie-report/ by default);
# mount a host directory here to keep them.
WORKDIR /reports

ENTRYPOINT ["/app/exe/cookiejar"]
CMD ["--help"]
