# frozen_string_literal: true

# One process: writes to the record files are serialised in it, and the rate limit is kept in memory.
workers 0
threads 1, Integer(ENV.fetch("PUMA_THREADS", "5"))
port Integer(ENV.fetch("PORT", "9292"))
environment ENV.fetch("RACK_ENV", "production")
