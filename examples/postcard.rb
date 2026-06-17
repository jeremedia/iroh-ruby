#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/postcard_demo"

begin
  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::PostcardDemo::DEFAULT_MESSAGE
            end

  result = Iroh::Examples::PostcardDemo.deliver(message)

  puts "iroh-ruby postcard demo"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "payload:  #{result.payload}"
  puts "success:  delivered #{result.payload.bytesize} bytes over loopback"
rescue StandardError => e
  warn "postcard failed: #{e.message}"
  exit 1
end
