# frozen_string_literal: true

require_relative "../lib/iroh"
require_relative "support/endpoint_watchers_demo"

begin
  result = Iroh::Examples::EndpointWatchersDemo.run_once
  online_status = if result.online_probe_completed
                    "completed"
                  else
                    "timed out after #{result.online_probe_timeout_ms}ms"
                  end

  puts "iroh-ruby endpoint watchers demo"
  puts "endpoint: #{result.endpoint_id}"
  puts "addr:     #{result.endpoint_addr}"
  puts "online:   #{online_status}"
  puts "latest:   #{result.latest_addr}"
  puts "direct:   #{result.latest_direct_addresses.join(', ')}"
  puts "relay:    #{result.latest_relay_url || 'none'}"
  puts "events:   addr=#{result.addr_event_count} home_relay=#{result.home_relay_event_count} " \
       "network=#{result.network_change_event_count}"
  puts "closed:   #{result.endpoint_closed}"
  puts "success:  watched endpoint readiness and stopped watcher handles"
rescue StandardError => e
  warn "endpoint watchers demo failed: #{e.message}"
  exit 1
end
