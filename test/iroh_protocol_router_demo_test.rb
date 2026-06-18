# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/protocol_router_demo"

class IrohProtocolRouterDemoTest < Minitest::Test
  def test_native_recorder_exposes_protocol_creator
    recorder = Iroh::ProtocolRouterEchoRecorder.new

    assert_instance_of Iroh::ProtocolCreator, recorder.creator
    assert_equal 0, recorder.created_count
    assert_equal 0, recorder.accepted_count
    assert_equal 0, recorder.shutdown_count
    assert_nil recorder.last_received
    assert_nil recorder.last_sent
    assert_nil recorder.last_error
  end

  def test_routes_bidirectional_request_through_protocol_router
    message = "hello router"
    result = Iroh::Examples::ProtocolRouterDemo.run_once(message)

    assert_equal Iroh::Examples::ProtocolRouterDemo::ALPN, result.alpn
    assert_equal message, result.sent
    assert_equal "routed: #{message}", result.received
    assert_equal 1, result.created_count
    assert_equal 1, result.accepted_count
    assert_equal 1, result.shutdown_count
    assert_equal message, result.last_received
    assert_equal "routed: #{message}", result.last_sent
    assert_nil result.last_error
    assert result.server_closed
    assert result.client_closed
    refute_empty result.ticket
    refute_empty result.server_id
    refute_empty result.client_id
  end

  def test_wrong_alpn_fails_visibly
    error = Iroh::Examples::ProtocolRouterDemo.reject_wrong_alpn(timeout: 5)

    assert_kind_of StandardError, error
    refute_equal "wrong ALPN connection unexpectedly succeeded", error.message
  end
end
