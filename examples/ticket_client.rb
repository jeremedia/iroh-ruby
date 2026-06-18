#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/ticket_exchange_demo"

begin
  ticket = ARGV.shift
  unless ticket
    warn "usage: bundle exec ruby examples/ticket_client.rb <ticket> [message...]"
    exit 1
  end

  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::TicketExchangeDemo::DEFAULT_MESSAGE
            end

  result = Iroh::Examples::TicketExchangeDemo::Client.deliver(ticket, message)

  puts "iroh-ruby ticket exchange client"
  puts "ticket:   #{result.ticket}"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "sent:     #{result.sent}"
  puts "received: #{result.received}"
  puts "success:  exchanged ticket across Ruby processes"
rescue StandardError => e
  warn "ticket client failed: #{e.message}"
  exit 1
end
