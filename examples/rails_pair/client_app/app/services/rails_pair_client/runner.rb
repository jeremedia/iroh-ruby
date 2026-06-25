# frozen_string_literal: true

module RailsPairClient
  class Runner
    def self.run
      config = Rails.application.config.x.iroh_pair
      ticket = ENV["IROH_RAILS_PAIR_TICKET"] || ARGV[0]
      unless ticket
        warn "usage: IROH_RAILS_PAIR_TICKET=<ticket> ruby examples/rails_pair/client_app/bin/rails runner RailsPairClient::Runner.run"
        exit 1
      end

      message = ENV["IROH_RAILS_PAIR_MESSAGE"] || ARGV[1..]&.join(" ")
      message = Iroh::Examples::RailsPairDemo::DEFAULT_MESSAGE if message.to_s.empty?
      commands = Iroh::Examples::RailsPairDemo.default_commands(message)
      result = Iroh::Examples::RailsPairDemo::Client.deliver(
        ticket,
        commands,
        timeout: config.timeout_seconds,
        app_name: config.app_name
      )

      puts "iroh-ruby Rails pair client"
      puts "ticket:   #{result.ticket}"
      puts "app:      #{result.app_name}"
      puts "rails:    #{Rails.version}"
      puts "sender:   #{result.sender_id}"
      puts "receiver: #{result.receiver_id}"
      puts "alpn:     #{result.alpn}"
      result.responses.each do |response|
        puts "response: #{Iroh::Examples::RailsPairDemo.encode_response(response)}"
      end
      puts "success:  exchanged JSON commands between Rails apps"
    rescue StandardError => e
      warn "Rails pair client failed: #{e.message}"
      exit 1
    end
  end
end
