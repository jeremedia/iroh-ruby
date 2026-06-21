#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/json_command_bridge_demo"

begin
  ticket = ARGV.shift
  unless ticket
    warn "usage: bundle exec ruby examples/json_command_client.rb <ticket> [echo-message...]"
    exit 1
  end

  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::JsonCommandBridgeDemo::DEFAULT_MESSAGE
            end
  commands = Iroh::Examples::JsonCommandBridgeDemo.default_commands(message)
  result = Iroh::Examples::JsonCommandBridgeDemo::Client.deliver(ticket, commands)

  puts "iroh-ruby JSON command bridge client"
  puts "ticket:   #{result.ticket}"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  result.responses.each do |response|
    puts "response: #{Iroh::Examples::JsonCommandBridgeDemo.encode_response(response)}"
  end
  puts "success:  exchanged JSON commands over Iroh streams"
rescue StandardError => e
  warn "JSON command client failed: #{e.message}"
  exit 1
end
