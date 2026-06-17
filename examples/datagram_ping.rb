#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/datagram_ping_demo"

begin
  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::DatagramPingDemo::DEFAULT_MESSAGE
            end

  result = Iroh::Examples::DatagramPingDemo.deliver(message)

  puts "iroh-ruby datagram ping demo"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "sent:     #{result.sent}"
  puts "received: #{result.received}"
  puts "success:  exchanged datagrams over loopback"
rescue StandardError => e
  warn "datagram ping failed: #{e.message}"
  exit 1
end
