# frozen_string_literal: true

require "test_helper"
require "stringio"
require "timeout"

class IrohJsonBridgeTest < Minitest::Test
  TEST_ALPN = "iroh-ruby/test/json-bridge"

  def test_encodes_and_decodes_commands_with_string_keys
    command = {
      request_id: "42",
      op: :echo,
      params: { message: "hello" }
    }

    assert_equal(
      {
        "request_id" => "42",
        "op" => "echo",
        "params" => { "message" => "hello" }
      },
      Iroh::JsonBridge.decode_command(Iroh::JsonBridge.encode_command(command))
    )
  end

  def test_rejects_non_object_commands_and_responses
    command_error = assert_raises(ArgumentError) do
      Iroh::JsonBridge.decode_command("[1,2,3]")
    end
    response_error = assert_raises(ArgumentError) do
      Iroh::JsonBridge.decode_response("[1,2,3]")
    end

    assert_equal "JSON command must be an object", command_error.message
    assert_equal "JSON response must be an object", response_error.message
  end

  def test_command_router_handles_success_unsupported_and_exceptions
    router = Iroh::JsonBridge::CommandRouter.new
    router.on("echo") { |command, _context| { "message" => command.dig("params", "message") } }
    router.on("boom") { raise "broken handler" }

    assert_equal(
      Iroh::JsonBridge.ok_response("1", "echo", "message" => "hello"),
      router.call("request_id" => "1", "op" => "echo", "params" => { "message" => "hello" })
    )
    assert_equal(
      Iroh::JsonBridge.error_response("2", "missing", "unsupported command: missing"),
      router.call("request_id" => "2", "op" => "missing")
    )
    assert_equal(
      Iroh::JsonBridge.error_response("3", "boom", "handler failed: broken handler"),
      router.call("request_id" => "3", "op" => "boom")
    )
  end

  def test_server_and_client_exchange_commands_over_loopback
    router = Iroh::JsonBridge::CommandRouter.new
    router.on("echo") { |command, _context| { "message" => command.dig("params", "message").to_s } }
    router.on("shutdown") { |_command, _context| { "shutdown" => true } }
    ticket_out = TicketOutput.new
    server_queue = Queue.new
    server = Iroh::JsonBridge::Server.new(
      endpoint_options: endpoint_options,
      alpn: TEST_ALPN,
      router: router,
      timeout: 10
    )
    server_thread = Thread.new do
      server_queue << server.run_once(out: ticket_out)
    rescue StandardError => e
      server_queue << e
    end

    ticket_line = Timeout.timeout(10, Timeout::Error, "timed out waiting for test server ticket") do
      ticket_out.queue.pop
    end
    ticket = ticket_line.sub(/\Aticket:\s*/, "")
    client = Iroh::JsonBridge::Client.new(
      endpoint_options: endpoint_options,
      alpn: TEST_ALPN,
      timeout: 10
    )
    client_result = client.deliver(
      ticket,
      [
        { "request_id" => "1", "op" => "echo", "params" => { "message" => "hello" } },
        { "request_id" => "2", "op" => "shutdown" }
      ]
    )
    server_result = Timeout.timeout(10, Timeout::Error, "timed out waiting for test server result") do
      server_queue.pop
    end
    raise server_result if server_result.is_a?(Exception)

    assert server_thread.join(0.1)
    assert_equal TEST_ALPN, client_result.alpn
    assert_equal TEST_ALPN, server_result.alpn
    assert_equal 2, client_result.responses.length
    assert_equal "hello", client_result.responses.first.fetch("result").fetch("message")
    assert Iroh::JsonBridge.shutdown_response?(client_result.responses.last)
    assert server_result.server_closed
  ensure
    server_thread&.kill if server_thread&.alive?
  end

  def test_endpoint_options_are_required
    router = Iroh::JsonBridge::CommandRouter.new

    server_error = assert_raises(ArgumentError) do
      Iroh::JsonBridge::Server.new(endpoint_options: nil, alpn: TEST_ALPN, router: router)
    end
    client_error = assert_raises(ArgumentError) do
      Iroh::JsonBridge::Client.new(endpoint_options: nil, alpn: TEST_ALPN)
    end

    assert_equal "endpoint_options is required", server_error.message
    assert_equal "endpoint_options is required", client_error.message
  end

  def endpoint_options
    Iroh::EndpointOptions.new(
      preset: Iroh.preset_minimal,
      relay_mode: Iroh::RelayMode.disabled,
      bind_addr: "127.0.0.1:0",
      alpns: [TEST_ALPN]
    )
  end

  class TicketOutput
    attr_reader :queue

    def initialize
      @queue = Queue.new
    end

    def puts(line)
      @queue << line
    end

    def flush; end
  end
end
