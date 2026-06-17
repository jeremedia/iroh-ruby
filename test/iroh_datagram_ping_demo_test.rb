# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "../examples/support/datagram_ping_demo"

class IrohDatagramPingDemoTest < Minitest::Test
  DEMO_TEST_TIMEOUT_SECONDS = Iroh::Examples::DatagramPingDemo::DEFAULT_TIMEOUT_SECONDS + 5

  def test_exchanges_ping_pong_datagrams_between_loopback_endpoints
    message = "hello from datagram land"

    result = Timeout.timeout(DEMO_TEST_TIMEOUT_SECONDS) do
      Iroh::Examples::DatagramPingDemo.deliver(message)
    end

    assert_equal "ping: #{message}", result.sent
    assert_equal "pong: #{message}", result.received
    assert_equal "iroh-ruby/demo/datagram-ping", result.alpn
    refute_empty result.sender_id
    refute_empty result.receiver_id
    assert result.sender_closed
    assert result.receiver_closed
  end
end
