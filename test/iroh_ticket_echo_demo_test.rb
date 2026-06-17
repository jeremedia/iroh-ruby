# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "../examples/support/ticket_echo_demo"

class IrohTicketEchoDemoTest < Minitest::Test
  DEMO_TEST_TIMEOUT_SECONDS = Iroh::Examples::TicketEchoDemo::DEFAULT_TIMEOUT_SECONDS + 5

  def test_delivers_echo_payload_through_serialized_endpoint_ticket
    message = "hello from ticket land"

    result = Timeout.timeout(DEMO_TEST_TIMEOUT_SECONDS) do
      Iroh::Examples::TicketEchoDemo.deliver(message)
    end

    assert_equal message, result.sent
    assert_equal "echo: #{message}", result.received
    assert_equal "iroh-ruby/demo/ticket-echo", result.alpn
    refute_empty result.ticket
    refute_empty result.sender_id
    refute_empty result.receiver_id
    assert result.sender_closed
    assert result.receiver_closed
  end
end
