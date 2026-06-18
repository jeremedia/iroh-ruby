#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$stdout.sync = true

require_relative "support/ticket_exchange_demo"

begin
  result = Iroh::Examples::TicketExchangeDemo::Server.run_once

  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "received: #{result.received}"
  puts "sent:     #{result.sent}"
  puts "success:  handled one ticket client"
rescue StandardError => e
  warn "ticket server failed: #{e.message}"
  exit 1
end
