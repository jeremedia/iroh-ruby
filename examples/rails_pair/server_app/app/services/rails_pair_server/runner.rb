# frozen_string_literal: true

module RailsPairServer
  class Runner
    def self.run
      $stdout.sync = true
      config = Rails.application.config.x.iroh_pair
      result = Iroh::Examples::RailsPairDemo::Server.run_once(
        timeout: config.timeout_seconds,
        out: $stdout,
        app_name: config.app_name,
        rails_env: Rails.env,
        rails_version: Rails.version
      )

      puts "server:   #{result.server_id}"
      puts "app:      #{result.app_name}"
      puts "rails:    #{Rails.version}"
      puts "alpn:     #{result.alpn}"
      puts "handled:  #{result.handled_commands}"
      result.responses.each do |response|
        puts "response: #{Iroh::Examples::RailsPairDemo.encode_response(response)}"
      end
      puts "success:  handled Rails pair client"
    rescue StandardError => e
      warn "Rails pair server failed: #{e.message}"
      exit 1
    end
  end
end
