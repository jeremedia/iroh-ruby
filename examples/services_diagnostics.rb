# frozen_string_literal: true

require_relative "../lib/iroh"
require_relative "support/services_diagnostics_demo"

begin
  result = Iroh::Examples::ServicesDiagnosticsDemo.run_once

  puts "iroh-ruby services diagnostics demo"
  puts "mode:     #{result.mode}"

  if result.mode == "skipped"
    puts "skipped:  #{result.skip_reason}"
    exit 0
  end

  puts "endpoint: #{result.endpoint_id}"
  puts "addr:     #{result.endpoint_addr}"
  puts "client:   #{result.client_constructed ? 'constructed' : 'not constructed'}"
  puts "ping:     #{result.ping_attempted ? 'attempted' : 'not attempted'}"
  puts "metrics:  #{result.metrics_pushed ? 'pushed' : 'not pushed'}"
  puts "diag:     #{result.diagnostics_attempted ? 'attempted' : 'not attempted'}"
  puts "send:     #{result.diagnostics_sent}"

  if result.diagnostics_summary
    summary = result.diagnostics_summary
    puts "summary:  endpoint=#{summary.endpoint_id} direct_addrs=#{summary.direct_addrs.length} " \
         "net_report=#{summary.has_net_report}"
  end

  puts "closed:   #{result.endpoint_closed}"
  puts "success:  exercised services diagnostics #{result.mode} path"
rescue StandardError => e
  warn "services diagnostics demo failed: #{e.message}"
  exit 1
end
