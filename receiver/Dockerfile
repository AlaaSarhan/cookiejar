# syntax=docker/dockerfile:1
ARG RUBY_VERSION=4.0

FROM ruby:${RUBY_VERSION}-slim AS gems
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache

FROM ruby:${RUBY_VERSION}-slim
LABEL org.opencontainers.image.title="cookiejar-receiver" \
      org.opencontainers.image.description="Append-only log of cookie consent records sent by the cookiejar consent banner" \
      org.opencontainers.image.licenses="MIT"
WORKDIR /app
ENV BUNDLE_WITHOUT=development:test \
    DATA_DIR=/data \
    PORT=9292
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY . .
RUN useradd --create-home --uid 1000 consentlog \
 && mkdir /data && chown consentlog /data
USER consentlog
# Keep the records on a persistent volume.
VOLUME /data
EXPOSE 9292
ENTRYPOINT ["bundle", "exec"]
CMD ["puma", "-C", "puma.rb"]
