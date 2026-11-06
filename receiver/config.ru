# frozen_string_literal: true

require "logger"
require_relative "lib/consent_log"

$stdout.sync = true
logger = Logger.new($stdout)
store = ConsentLog::Store.new(ConsentLog::Settings.data_dir, logger: logger)
at_exit { store.close }

run ConsentLog::App.new(
  store: store,
  allowed_origins: ConsentLog::Settings.allowed_origins,
  admin_token: ConsentLog::Settings.admin_token,
  rate_limit: ConsentLog::Settings.rate_limit,
  logger: logger
)
