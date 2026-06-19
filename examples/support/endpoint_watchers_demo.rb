# frozen_string_literal: true

require_relative "loopback_support"

module Iroh
  module Examples
    module EndpointWatchersDemo
      DEFAULT_TIMEOUT_SECONDS = 10
      ONLINE_PROBE_TIMEOUT_MS = 250

      Result = Struct.new(
        :endpoint_id,
        :endpoint_addr,
        :online_probe_completed,
        :online_probe_timeout_ms,
        :latest_addr,
        :latest_addr_id,
        :latest_direct_addresses,
        :latest_relay_url,
        :addr_event_count,
        :home_relay_event_count,
        :latest_home_relay_urls,
        :network_change_event_count,
        :endpoint_closed,
        keyword_init: true
      )

      module_function

      def run_once(timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        endpoint = bind_endpoint
        handles = []

        online_probe_completed = probe_online(endpoint, timeout_ms: ONLINE_PROBE_TIMEOUT_MS)

        addr_recorder = Iroh::AddrChangeRecorder.new
        home_relay_recorder = Iroh::HomeRelayRecorder.new
        network_change_recorder = Iroh::NetworkChangeRecorder.new

        handles << endpoint.watch_addr(addr_recorder.callback)
        handles << endpoint.watch_home_relay(home_relay_recorder.callback)
        handles << endpoint.watch_network_change(network_change_recorder.callback)

        wait_for_addr_event(addr_recorder, deadline)
        latest_addr = addr_recorder.latest_addr

        stop_watch_handles(handles)
        close_endpoint(endpoint)

        Result.new(
          endpoint_id: endpoint.id.to_s,
          endpoint_addr: endpoint.addr.to_s,
          online_probe_completed: online_probe_completed,
          online_probe_timeout_ms: ONLINE_PROBE_TIMEOUT_MS,
          latest_addr: latest_addr&.to_s,
          latest_addr_id: latest_addr&.id&.to_s,
          latest_direct_addresses: latest_addr&.direct_addresses || [],
          latest_relay_url: latest_addr&.relay_url,
          addr_event_count: addr_recorder.event_count,
          home_relay_event_count: home_relay_recorder.event_count,
          latest_home_relay_urls: home_relay_recorder.latest_relay_urls,
          network_change_event_count: network_change_recorder.event_count,
          endpoint_closed: endpoint.is_closed
        )
      ensure
        stop_watch_handles(handles)
        close_endpoint(endpoint)
      end

      def bind_endpoint
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0"
          )
        )
      end

      def probe_online(endpoint, timeout_ms: ONLINE_PROBE_TIMEOUT_MS)
        Timeout.timeout(timeout_ms / 1000.0) do
          endpoint.online
          true
        end
      rescue Timeout::Error
        false
      end

      def wait_for_addr_event(recorder, deadline)
        timeout_ms = [(remaining_timeout(deadline, "timed out waiting for address watcher") * 1000).ceil, 1].max
        return if recorder.wait_for_events(1, timeout_ms)

        raise Timeout::Error, "timed out waiting for address watcher event"
      end

      def stop_watch_handles(handles)
        Array(handles).compact.each do |handle|
          # Stop twice to keep the demo honest about idempotent teardown.
          handle.stop
          handle.stop
        rescue StandardError
          nil
        end
      end

      def close_endpoint(endpoint)
        LoopbackSupport.close_endpoint(endpoint)
      end

      def with_deadline_timeout(deadline, message)
        LoopbackSupport.with_deadline_timeout(deadline, message) { yield }
      end

      def remaining_timeout(deadline, message)
        LoopbackSupport.remaining_timeout(deadline, message)
      end

      def normalize_timeout_seconds(timeout)
        LoopbackSupport.normalize_timeout_seconds(timeout)
      end

      def monotonic_time
        LoopbackSupport.monotonic_time
      end
    end
  end
end
