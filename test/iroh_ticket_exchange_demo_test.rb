# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"
require_relative "../examples/support/ticket_exchange_demo"

class IrohTicketExchangeDemoTest < Minitest::Test
  DEMO_TEST_TIMEOUT_SECONDS = Iroh::Examples::TicketExchangeDemo::DEFAULT_TIMEOUT_SECONDS + 5

  def test_exchanges_echo_payload_through_ticket_across_independent_demo_roles
    writer = QueueWriter.new
    server_result_queue = Queue.new
    message = "hello from another ruby process"

    Timeout.timeout(DEMO_TEST_TIMEOUT_SECONDS) do
      server_thread = Thread.new do
        server_result_queue << Iroh::Examples::TicketExchangeDemo::Server.run_once(out: writer)
      rescue StandardError => e
        server_result_queue << e
      end

      ticket_line = writer.pop_line
      assert_match(/\Aticket: /, ticket_line)
      ticket = ticket_line.sub(/\Aticket:\s*/, "")

      client_result = Iroh::Examples::TicketExchangeDemo::Client.deliver(ticket, message)
      server_result = server_result_queue.pop
      server_thread.join

      raise server_result if server_result.is_a?(Exception)

      assert_equal message, client_result.sent
      assert_equal "echo: #{message}", client_result.received
      assert_equal "iroh-ruby/demo/ticket-exchange", client_result.alpn
      assert_equal ticket, client_result.ticket
      refute_empty client_result.sender_id
      refute_empty client_result.receiver_id
      assert client_result.sender_closed

      assert_equal message, server_result.received
      assert_equal "echo: #{message}", server_result.sent
      assert_equal ticket, server_result.ticket
      assert server_result.receiver_closed
    end
  end

  def test_client_rejects_invalid_ticket_without_waiting_for_network_io
    error = assert_raises(StandardError) do
      Iroh::Examples::TicketExchangeDemo::Client.deliver("not-a-ticket", "hello", timeout: 0.5)
    end

    refute_empty error.message
  end

  def test_rake_smoke_task_exchanges_ticket_across_ruby_processes
    stdout, stderr, status = Timeout.timeout(DEMO_TEST_TIMEOUT_SECONDS + 10) do
      Open3.capture3("bundle", "exec", "rake", "demo:ticket_exchange")
    end

    assert status.success?, stderr
    assert_includes stdout, "iroh-ruby ticket exchange demo"
    assert_includes stdout, "ticket:"
    assert_includes stdout, "sent:     hello from another ruby process"
    assert_includes stdout, "received: echo: hello from another ruby process"
    assert_includes stdout, "success:  exchanged ticket across Ruby processes"
  end

  class QueueWriter
    def initialize
      @lines = Queue.new
    end

    def puts(line)
      @lines << line.to_s
    end

    def flush; end

    def pop_line
      @lines.pop
    end
  end
end
