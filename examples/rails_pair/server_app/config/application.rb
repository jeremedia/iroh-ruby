# frozen_string_literal: true

require_relative "boot"
require "logger"
require "rails"

Bundler.require(:default, Rails.env)

module RailsPairServer
  class Application < Rails::Application
    config.load_defaults 8.1
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.logger = Logger.new($stderr)
    config.log_level = :warn
    config.paths.add "app/services", eager_load: true

    config.x.iroh_pair.app_name = "server_app"
    config.x.iroh_pair.timeout_seconds = ENV.fetch("IROH_RAILS_PAIR_TIMEOUT", "20").to_f
  end
end
