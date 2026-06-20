# frozen_string_literal: true

require "test_helper"

support_path = File.expand_path("../examples/support/services_diagnostics_demo", __dir__)
require support_path if File.file?("#{support_path}.rb")

class IrohServicesDiagnosticsDemoTest < Minitest::Test
  def test_dry_run_constructs_services_client_without_live_credentials
    assert defined?(Iroh::Examples::ServicesDiagnosticsDemo),
           "expected services diagnostics demo support module to be defined"

    result = Iroh::Examples::ServicesDiagnosticsDemo.run_once(
      env: {},
      timeout: 10
    )

    assert_equal "dry", result.mode
    refute result.live
    assert result.client_constructed
    refute result.ping_attempted
    refute result.metrics_pushed
    refute result.diagnostics_attempted
    refute result.diagnostics_sent
    refute_empty result.endpoint_id
    refute_empty result.endpoint_addr
    assert result.endpoint_closed
    assert_nil result.diagnostics_summary
  end

  def test_live_mode_is_skipped_without_explicit_env
    assert defined?(Iroh::Examples::ServicesDiagnosticsDemo),
           "expected services diagnostics demo support module to be defined"

    result = Iroh::Examples::ServicesDiagnosticsDemo.run_once(
      env: { "IROH_SERVICES_LIVE" => "1" },
      timeout: 10
    )

    assert_equal "skipped", result.mode
    refute result.live
    assert_equal "set IROH_SERVICES_API_SECRET to run live services diagnostics", result.skip_reason
    refute result.client_constructed
    assert_nil result.endpoint_id
    assert_nil result.endpoint_addr
    assert_nil result.endpoint_closed
  end

  def test_live_mode_runs_only_when_real_env_is_present
    assert defined?(Iroh::Examples::ServicesDiagnosticsDemo),
           "expected services diagnostics demo support module to be defined"

    skip "set IROH_SERVICES_LIVE=1 and IROH_SERVICES_API_SECRET to run live services diagnostics" unless ENV["IROH_SERVICES_LIVE"] == "1" && ENV["IROH_SERVICES_API_SECRET"]

    result = Iroh::Examples::ServicesDiagnosticsDemo.run_once(
      env: ENV.to_h,
      timeout: 30
    )

    assert_equal "live", result.mode
    assert result.live
    assert result.client_constructed
    assert result.ping_attempted
    assert result.metrics_pushed
    assert result.diagnostics_attempted
    assert_equal ENV["IROH_SERVICES_SEND"] == "1", result.diagnostics_sent
    assert_instance_of Iroh::DiagnosticsSummary, result.diagnostics_summary
    assert result.endpoint_closed
  end
end
