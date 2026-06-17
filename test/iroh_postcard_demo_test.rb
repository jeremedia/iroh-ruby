# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/postcard_demo"

class IrohPostcardDemoTest < Minitest::Test
  def test_delivers_text_payload_between_loopback_endpoints
    message = "hello from ruby iroh"

    result = Iroh::Examples::PostcardDemo.deliver(message)

    assert_equal message, result.payload
    assert_equal "iroh-ruby/demo/postcard", result.alpn
    refute_empty result.sender_id
    refute_empty result.receiver_id
    assert result.sender_closed
    assert result.receiver_closed
  end
end
