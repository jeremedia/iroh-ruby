#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
$stdout.sync = true

require_relative "support/connection_telemetry_demo"

module ConnectionTelemetryCli
  module_function

  def run(argv)
    mode = argv.shift

    case mode
    when "server"
      run_server
    when "client"
      run_client(argv)
    when nil
      run_process_demo(argv)
    else
      warn "usage: bundle exec ruby examples/connection_telemetry.rb [server|client <ticket> [message...]]"
      1
    end
  end

  def run_server
    result = Iroh::Examples::ConnectionTelemetryDemo::Server.run_once

    puts "receiver: #{result.receiver_id}"
    puts "alpn:     #{result.alpn}"
    puts "received: #{result.received}"
    puts "sent:     #{result.sent}"
    puts Iroh::Examples::ConnectionTelemetryDemo.format_telemetry("server", result.telemetry)
    puts "success:  captured server-side connection telemetry"
    0
  end

  def run_client(argv)
    ticket = argv.shift
    unless ticket
      warn "usage: bundle exec ruby examples/connection_telemetry.rb client <ticket> [message...]"
      return 1
    end

    message = if argv.any?
                argv.join(" ")
              else
                Iroh::Examples::ConnectionTelemetryDemo::DEFAULT_MESSAGE
              end

    result = Iroh::Examples::ConnectionTelemetryDemo::Client.deliver(ticket, message)

    puts "iroh-ruby connection telemetry client"
    puts "ticket:   #{result.ticket}"
    puts "sender:   #{result.sender_id}"
    puts "receiver: #{result.receiver_id}"
    puts "alpn:     #{result.alpn}"
    puts "sent:     #{result.sent}"
    puts "received: #{result.received}"
    puts Iroh::Examples::ConnectionTelemetryDemo.format_telemetry("client", result.telemetry)
    puts "success:  captured client-side connection telemetry"
    0
  end

  def run_process_demo(argv)
    message = if argv.any?
                argv.join(" ")
              else
                Iroh::Examples::ConnectionTelemetryDemo::DEFAULT_MESSAGE
              end
    result = Iroh::Examples::ConnectionTelemetryDemo.run_process_demo(message)

    puts "iroh-ruby connection telemetry demo"
    puts "ticket:   #{result.ticket}"
    puts result.client_stdout
    puts result.server_stdout
    0
  end
end

begin
  exit ConnectionTelemetryCli.run(ARGV)
rescue StandardError => e
  warn "connection telemetry demo failed: #{e.message}"
  exit 1
end
