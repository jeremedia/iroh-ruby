#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$stdout.sync = true

require_relative "support/json_command_bridge_demo"

begin
  result = Iroh::Examples::JsonCommandBridgeDemo::Server.run_once

  puts "server:   #{result.server_id}"
  puts "alpn:     #{result.alpn}"
  puts "handled:  #{result.handled_commands}"
  result.responses.each do |response|
    puts "response: #{Iroh::Examples::JsonCommandBridgeDemo.encode_response(response)}"
  end
  puts "success:  handled JSON command bridge client"
rescue StandardError => e
  warn "JSON command server failed: #{e.message}"
  exit 1
end
