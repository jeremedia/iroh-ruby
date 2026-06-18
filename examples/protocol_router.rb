# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require_relative "support/protocol_router_demo"

message = ARGV.fetch(0, Iroh::Examples::ProtocolRouterDemo::DEFAULT_MESSAGE)

begin
  result = Iroh::Examples::ProtocolRouterDemo.run_once(message)

  puts "iroh-ruby protocol router demo"
  puts "server:   #{result.server_id}"
  puts "client:   #{result.client_id}"
  puts "ticket:   #{result.ticket}"
  puts "alpn:     #{result.alpn}"
  puts "sent:     #{result.sent}"
  puts "received: #{result.received}"
  puts "handler:  created=#{result.created_count} accepted=#{result.accepted_count} shutdown=#{result.shutdown_count}"
  puts "success:  routed through EndpointOptions.protocols"
rescue StandardError => e
  warn "protocol router demo failed: #{e.message}"
  exit 1
end
