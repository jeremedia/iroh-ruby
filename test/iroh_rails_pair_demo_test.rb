# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/rails_pair_demo"

class IrohRailsPairDemoTest < Minitest::Test
  def test_defines_rails_pair_protocol_metadata
    assert_equal "iroh-ruby/demo/rails-pair", Iroh::Examples::RailsPairDemo::ALPN
    assert_equal "hello from rails pair", Iroh::Examples::RailsPairDemo::DEFAULT_MESSAGE
    assert_equal 20, Iroh::Examples::RailsPairDemo::DEFAULT_TIMEOUT_SECONDS
  end

  def test_rejects_blank_ticket_before_network_io
    error = assert_raises(ArgumentError) do
      Iroh::Examples::RailsPairDemo.normalize_ticket(" \n ")
    end

    assert_equal "ticket is required", error.message
  end

  def test_exchanges_json_commands_between_two_rails_apps
    message = "hello rails pair"
    result = Iroh::Examples::RailsPairDemo.run_process_demo(message, timeout: 25)

    assert_equal message, result.message
    refute_empty result.ticket
    assert_includes result.client_stdout, "success:  exchanged JSON commands between Rails apps"
    assert_includes result.server_stdout, "success:  handled Rails pair client"
    assert_equal 5, result.responses.length

    echo, identify, stats, unsupported, shutdown = result.responses
    assert echo.fetch("ok")
    assert_equal "echo", echo.fetch("op")
    assert_equal message, echo.fetch("result").fetch("message")

    assert identify.fetch("ok")
    assert_equal "identify", identify.fetch("op")
    assert_equal Iroh::Examples::RailsPairDemo::ALPN, identify.fetch("result").fetch("alpn")
    assert_equal "server_app", identify.fetch("result").fetch("server_app")
    assert_equal "development", identify.fetch("result").fetch("rails_env")
    refute_empty identify.fetch("result").fetch("rails_version")

    assert stats.fetch("ok")
    assert_equal "stats", stats.fetch("op")
    assert_operator stats.fetch("result").fetch("handled_commands"), :>=, 3
    assert_operator stats.fetch("result").fetch("paths"), :>=, 1
    assert_equal "server_app", stats.fetch("result").fetch("server_app")

    refute unsupported.fetch("ok")
    assert_equal "does-not-exist", unsupported.fetch("op")
    assert_equal "unsupported command: does-not-exist", unsupported.fetch("error")

    assert shutdown.fetch("ok")
    assert_equal "shutdown", shutdown.fetch("op")
    assert shutdown.fetch("result").fetch("shutdown")
  end
end
