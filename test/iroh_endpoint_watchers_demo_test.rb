# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/endpoint_watchers_demo"

class IrohEndpointWatchersDemoTest < Minitest::Test
  def test_native_recorders_expose_callback_handles
    addr_recorder = Iroh::AddrChangeRecorder.new
    home_relay_recorder = Iroh::HomeRelayRecorder.new
    network_change_recorder = Iroh::NetworkChangeRecorder.new

    assert_instance_of Iroh::AddrChangeCallback, addr_recorder.callback
    assert_instance_of Iroh::HomeRelayCallback, home_relay_recorder.callback
    assert_instance_of Iroh::NetworkChangeCallback, network_change_recorder.callback
    assert_equal 0, addr_recorder.event_count
    assert_nil addr_recorder.latest_addr
    assert_equal 0, home_relay_recorder.event_count
    assert_equal [], home_relay_recorder.latest_relay_urls
    assert_equal 0, network_change_recorder.event_count
    refute addr_recorder.wait_for_events(1, 1)
  end

  def test_endpoint_online_and_address_watcher_lifecycle
    result = Iroh::Examples::EndpointWatchersDemo.run_once

    assert result.endpoint_closed
    refute result.online_probe_completed
    assert_equal Iroh::Examples::EndpointWatchersDemo::ONLINE_PROBE_TIMEOUT_MS, result.online_probe_timeout_ms
    assert_operator result.addr_event_count, :>=, 1
    assert_equal result.endpoint_id, result.latest_addr_id
    refute_empty result.endpoint_addr
    refute_empty result.latest_addr
    refute_empty result.latest_direct_addresses
    assert_nil result.latest_relay_url
    assert_operator result.home_relay_event_count, :>=, 0
    assert_kind_of Array, result.latest_home_relay_urls
    assert_operator result.network_change_event_count, :>=, 0
  end

  def test_watch_handle_stop_is_idempotent_for_demo_teardown
    endpoint = Iroh::Examples::EndpointWatchersDemo.bind_endpoint
    refute Iroh::Examples::EndpointWatchersDemo.probe_online(endpoint, timeout_ms: 50)
    recorder = Iroh::AddrChangeRecorder.new
    handle = endpoint.watch_addr(recorder.callback)

    assert recorder.wait_for_events(1, 5_000)

    handle.stop
    handle.stop
    Iroh::Examples::EndpointWatchersDemo.close_endpoint(endpoint)

    assert endpoint.is_closed
  ensure
    handle&.stop
    Iroh::Examples::EndpointWatchersDemo.close_endpoint(endpoint)
  end
end
