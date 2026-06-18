# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/ticket_exchange_demo"

class IrohTicketExchangeDemoTest < Minitest::Test
  def test_defines_process_exchange_protocol_metadata
    assert_equal "iroh-ruby/demo/ticket-exchange", Iroh::Examples::TicketExchangeDemo::ALPN
    assert_equal "hello from another ruby process", Iroh::Examples::TicketExchangeDemo::DEFAULT_MESSAGE
  end

  def test_normalizes_ticket_strings_for_command_line_copy_paste
    assert_equal "endpoint-ticket", Iroh::Examples::TicketExchangeDemo.normalize_ticket("  endpoint-ticket\n")
  end

  def test_rejects_blank_ticket_without_waiting_for_network_io
    error = assert_raises(ArgumentError) do
      Iroh::Examples::TicketExchangeDemo::Client.deliver("  ", "hello")
    end

    assert_equal "ticket is required", error.message
  end
end
