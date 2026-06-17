#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/ticket_echo_demo"

begin
  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::TicketEchoDemo::DEFAULT_MESSAGE
            end

  result = Iroh::Examples::TicketEchoDemo.deliver(message)

  puts "iroh-ruby ticket echo demo"
  puts "ticket:   #{result.ticket}"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "sent:     #{result.sent}"
  puts "received: #{result.received}"
  puts "success:  connected via serialized endpoint ticket"
rescue StandardError => e
  warn "ticket echo failed: #{e.message}"
  exit 1
end
