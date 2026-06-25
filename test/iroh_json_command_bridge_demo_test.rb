# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/json_command_bridge_demo"

class IrohJsonCommandBridgeDemoTest < Minitest::Test
  def test_defines_application_protocol_metadata
    assert_equal "iroh-ruby/demo/json-command-bridge", Iroh::Examples::JsonCommandBridgeDemo::ALPN
    assert_equal "hello from json bridge", Iroh::Examples::JsonCommandBridgeDemo::DEFAULT_MESSAGE
    assert_equal 16, Iroh::Examples::JsonCommandBridgeDemo::MAX_COMMANDS
  end

  def test_encodes_and_decodes_json_commands_with_string_keys
    command = {
      request_id: "42",
      op: :echo,
      params: {
        message: "hello"
      }
    }

    decoded = Iroh::Examples::JsonCommandBridgeDemo.decode_command(
      Iroh::Examples::JsonCommandBridgeDemo.encode_command(command)
    )

    assert_equal Iroh::JsonBridge.encode_command(command),
                 Iroh::Examples::JsonCommandBridgeDemo.encode_command(command)
    assert_equal(
      {
        "request_id" => "42",
        "op" => "echo",
        "params" => {
          "message" => "hello"
        }
      },
      decoded
    )
  end

  def test_rejects_non_object_commands_before_network_io
    error = assert_raises(ArgumentError) do
      Iroh::Examples::JsonCommandBridgeDemo.decode_command("[1,2,3]")
    end

    assert_equal "JSON command must be an object", error.message
  end

  def test_unsupported_command_returns_structured_error
    response = Iroh::Examples::JsonCommandBridgeDemo.response_for(
      { "request_id" => "nope", "op" => "missing" },
      {
        server_id: "server",
        remote_id: "client",
        handled_commands: 1,
        connection_stable_id: "stable",
        paths: 1
      }
    )

    refute response.fetch("ok")
    assert_equal Iroh::JsonBridge.error_response("nope", "missing", "unsupported command: missing"),
                 response
    assert_equal "nope", response.fetch("request_id")
    assert_equal "missing", response.fetch("op")
    assert_equal "unsupported command: missing", response.fetch("error")
  end

  def test_exchanges_multiple_json_commands_across_processes
    message = "hello bridge test"
    result = Iroh::Examples::JsonCommandBridgeDemo.run_process_demo(message, timeout: 20)

    assert_equal message, result.message
    refute_empty result.ticket
    assert_includes result.client_stdout, "success:  exchanged JSON commands over Iroh streams"
    assert_includes result.server_stdout, "success:  handled JSON command bridge client"
    assert_equal 5, result.responses.length

    echo, identify, stats, unsupported, shutdown = result.responses
    assert echo.fetch("ok")
    assert_equal "echo", echo.fetch("op")
    assert_equal message, echo.fetch("result").fetch("message")

    assert identify.fetch("ok")
    assert_equal "identify", identify.fetch("op")
    refute_empty identify.fetch("result").fetch("server_id")
    refute_empty identify.fetch("result").fetch("remote_id")
    assert_equal Iroh::Examples::JsonCommandBridgeDemo::ALPN, identify.fetch("result").fetch("alpn")

    assert stats.fetch("ok")
    assert_equal "stats", stats.fetch("op")
    assert_operator stats.fetch("result").fetch("handled_commands"), :>=, 3
    assert_operator stats.fetch("result").fetch("paths"), :>=, 1

    refute unsupported.fetch("ok")
    assert_equal "does-not-exist", unsupported.fetch("op")
    assert_equal "unsupported command: does-not-exist", unsupported.fetch("error")

    assert shutdown.fetch("ok")
    assert_equal "shutdown", shutdown.fetch("op")
    assert shutdown.fetch("result").fetch("shutdown")
  end
end
