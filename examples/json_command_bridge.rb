#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/json_command_bridge_demo"

begin
  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::JsonCommandBridgeDemo::DEFAULT_MESSAGE
            end
  result = Iroh::Examples::JsonCommandBridgeDemo.run_process_demo(message)

  puts "iroh-ruby JSON command bridge demo"
  puts "ticket:   #{result.ticket}"
  puts result.client_stdout
  puts result.server_stdout
rescue StandardError => e
  warn "JSON command bridge demo failed: #{e.message}"
  exit 1
end
