#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require_relative "support/rails_pair_demo"

begin
  message = if ARGV.any?
              ARGV.join(" ")
            else
              Iroh::Examples::RailsPairDemo::DEFAULT_MESSAGE
            end
  result = Iroh::Examples::RailsPairDemo.run_process_demo(message)

  puts "iroh-ruby Rails pair demo"
  puts "ticket:   #{result.ticket}"
  puts result.client_stdout
  puts result.server_stdout
rescue StandardError => e
  warn "Rails pair demo failed: #{e.message}"
  exit 1
end
