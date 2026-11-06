# syntax=docker/dockerfile:1
ARG RUBY_VERSION=4.0

# Gems with native extensions (json) need a compiler, kept out of the final image.
FROM ruby:${RUBY_VERSION}-slim AS gems

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test

COPY Gemfile Gemfile.lock cookiejar-consent.gemspec ./
COPY lib/cookiejar_consent/version.rb lib/cookiejar_consent/

RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache

FROM ruby:${RUBY_VERSION}-slim

LABEL org.opencontainers.image.title="cookiejar-consent" \
      org.opencontainers.image.description="Builds a cookie consent banner with Google Consent Mode v2 from a cookiejar scan report" \
      org.opencontainers.image.licenses="MIT"

WORKDIR /app

ENV BUNDLE_WITHOUT=development:test

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY . .

RUN useradd --create-home --uid 1000 cookiejar \
 && mkdir /work && chown cookiejar /work

USER cookiejar

# Reports are read from, and the banner written to, paths relative to the
# working directory; mount the directory holding cookie-report/ here.
WORKDIR /work

ENTRYPOINT ["/app/exe/cookiejar-consent"]
CMD ["--help"]
