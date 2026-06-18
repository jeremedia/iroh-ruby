# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/connection_telemetry_demo"

class IrohConnectionTelemetryDemoTest < Minitest::Test
  PathStats = Struct.new(
    :rtt_ms,
    :udp_tx_datagrams,
    :udp_tx_bytes,
    :udp_rx_datagrams,
    :udp_rx_bytes,
    :cwnd,
    :congestion_events,
    :lost_packets,
    :lost_bytes,
    :current_mtu,
    keyword_init: true
  )
  PathSnapshot = Struct.new(
    :id,
    :is_selected,
    :remote_addr,
    :is_ip,
    :is_relay,
    :rtt_ms,
    :stats,
    keyword_init: true
  )
  ConnectionStats = Struct.new(
    :udp_tx_datagrams,
    :udp_tx_bytes,
    :udp_rx_datagrams,
    :udp_rx_bytes,
    :lost_packets,
    :lost_bytes,
    keyword_init: true
  )
  CounterStats = Struct.new(:value, :description, keyword_init: true)
  FakeConnection = Struct.new(:remote_id, :stable_id, :side, :rtt, :stats, :paths, keyword_init: true)
  FakeEndpoint = Struct.new(:id, :stats, keyword_init: true) do
    def online
      raise "endpoint.online should not be called by snapshot telemetry"
    end

    def remote_addr(_remote_id)
      "127.0.0.1:5000"
    end
  end

  def test_defines_connection_telemetry_protocol_metadata
    assert_equal "iroh-ruby/demo/connection-telemetry", Iroh::Examples::ConnectionTelemetryDemo::ALPN
    assert_equal "hello from telemetry land", Iroh::Examples::ConnectionTelemetryDemo::DEFAULT_MESSAGE
  end

  def test_serializes_connection_and_path_telemetry_to_stable_hashes
    snapshot = Iroh::Examples::ConnectionTelemetryDemo.telemetry_snapshot(
      endpoint: fake_endpoint,
      connection: fake_connection,
      remote_id: "receiver-id"
    )

    assert_equal "sender-id", snapshot[:endpoint_id]
    assert_nil snapshot[:endpoint_online]
    assert_equal "127.0.0.1:5000", snapshot[:endpoint_remote_addr]
    assert_equal "receiver-id", snapshot[:connection][:remote_id]
    assert_equal 42, snapshot[:connection][:stable_id]
    assert_equal "CLIENT", snapshot[:connection][:side]
    assert_equal 7, snapshot[:connection][:rtt_ms]
    assert_equal({ udp_tx_datagrams: 4, udp_tx_bytes: 128, udp_rx_datagrams: 3, udp_rx_bytes: 96,
                   lost_packets: 1, lost_bytes: 2 }, snapshot[:connection][:stats])
    assert_equal({ total: 2, selected: 1, relay: 1, rtt_observed: true }, snapshot[:path_summary])
    assert_equal ["conn_bytes_sent"], snapshot[:endpoint_stats].keys
    assert_equal({ value: 128, description: "bytes sent" }, snapshot[:endpoint_stats]["conn_bytes_sent"])
  end

  def test_formats_missing_optional_telemetry_without_exact_counter_expectations
    snapshot = Iroh::Examples::ConnectionTelemetryDemo.telemetry_snapshot(
      endpoint: fake_endpoint,
      connection: fake_connection(rtt: nil, paths: []),
      remote_id: nil
    )
    lines = Iroh::Examples::ConnectionTelemetryDemo.format_telemetry("client", snapshot)

    assert_includes lines, "client endpoint: id=sender-id online=unknown remote_addr=unknown"
    assert_includes lines, "client connection: remote=receiver-id stable_id=42 side=CLIENT rtt_ms=unknown"
    assert_includes lines, "client paths: total=0 selected=0 relay=0 rtt_observed=false"
  end

  private

  def fake_endpoint
    FakeEndpoint.new(
      id: "sender-id",
      stats: {
        "conn_bytes_sent" => CounterStats.new(value: 128, description: "bytes sent")
      }
    )
  end

  def fake_connection(rtt: 7, paths: fake_paths)
    FakeConnection.new(
      remote_id: "receiver-id",
      stable_id: 42,
      side: "CLIENT",
      rtt: rtt,
      stats: ConnectionStats.new(
        udp_tx_datagrams: 4,
        udp_tx_bytes: 128,
        udp_rx_datagrams: 3,
        udp_rx_bytes: 96,
        lost_packets: 1,
        lost_bytes: 2
      ),
      paths: paths
    )
  end

  def fake_paths
    [
      PathSnapshot.new(
        id: 1,
        is_selected: true,
        remote_addr: "127.0.0.1:5000",
        is_ip: true,
        is_relay: false,
        rtt_ms: 7,
        stats: PathStats.new(
          rtt_ms: 7,
          udp_tx_datagrams: 4,
          udp_tx_bytes: 128,
          udp_rx_datagrams: 3,
          udp_rx_bytes: 96,
          cwnd: 12_000,
          congestion_events: 0,
          lost_packets: 0,
          lost_bytes: 0,
          current_mtu: 1_200
        )
      ),
      PathSnapshot.new(
        id: 2,
        is_selected: false,
        remote_addr: "relay.example.test",
        is_ip: false,
        is_relay: true,
        rtt_ms: nil,
        stats: nil
      )
    ]
  end
end
