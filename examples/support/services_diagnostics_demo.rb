# frozen_string_literal: true

require_relative "loopback_support"

module Iroh
  module Examples
    module ServicesDiagnosticsDemo
      DEFAULT_TIMEOUT_SECONDS = 30
      FAKE_API_SECRET = "servicesaaqaobyha4dqobyha4dqobyha4dqobyha4dqobyha4dqobyha4dqob75c4sdqwvay5nwj63yzvqc7iozsh66x53lcpcy5vyc5ledl2pwdaaa"
      LIVE_SKIP_REASON = "set IROH_SERVICES_API_SECRET to run live services diagnostics"

      Result = Struct.new(
        :mode,
        :live,
        :skip_reason,
        :endpoint_id,
        :endpoint_addr,
        :client_constructed,
        :ping_attempted,
        :metrics_pushed,
        :diagnostics_attempted,
        :diagnostics_sent,
        :diagnostics_summary,
        :endpoint_closed,
        keyword_init: true
      )

      module_function

      def run_once(env: ENV.to_h, timeout: DEFAULT_TIMEOUT_SECONDS)
        if live_requested?(env)
          return skipped_result unless env["IROH_SERVICES_API_SECRET"]

          run_live(env: env, timeout: timeout)
        else
          run_dry(timeout: timeout)
        end
      end

      def run_dry(timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        endpoint = bind_dry_endpoint
        client = nil

        client = with_deadline_timeout(deadline, "timed out constructing dry services client") do
          Iroh::ServicesClient.create(
            endpoint,
            Iroh::ServicesOptions.new(
              api_secret: FAKE_API_SECRET,
              metrics_interval_ms: 0
            )
          )
        end

        close_endpoint(endpoint)

        Result.new(
          mode: "dry",
          live: false,
          endpoint_id: endpoint.id.to_s,
          endpoint_addr: endpoint.addr.to_s,
          client_constructed: !client.nil?,
          ping_attempted: false,
          metrics_pushed: false,
          diagnostics_attempted: false,
          diagnostics_sent: false,
          diagnostics_summary: nil,
          endpoint_closed: endpoint.is_closed
        )
      ensure
        close_endpoint(endpoint)
      end

      def run_live(env:, timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        endpoint = bind_live_endpoint
        client = nil
        send_diagnostics = send_requested?(env)

        client = with_deadline_timeout(deadline, "timed out constructing live services client") do
          Iroh::ServicesClient.create(
            endpoint,
            Iroh::ServicesOptions.new(
              api_secret: env.fetch("IROH_SERVICES_API_SECRET"),
              metrics_interval_ms: 0
            )
          )
        end
        with_deadline_timeout(deadline, "timed out pinging iroh services") do
          client.ping
        end
        with_deadline_timeout(deadline, "timed out pushing iroh services metrics") do
          client.push_metrics
        end
        diagnostics_summary = with_deadline_timeout(deadline, "timed out running iroh services diagnostics") do
          client.submit_network_diagnostics(send_diagnostics)
        end

        close_endpoint(endpoint)

        Result.new(
          mode: "live",
          live: true,
          endpoint_id: endpoint.id.to_s,
          endpoint_addr: endpoint.addr.to_s,
          client_constructed: !client.nil?,
          ping_attempted: true,
          metrics_pushed: true,
          diagnostics_attempted: true,
          diagnostics_sent: send_diagnostics,
          diagnostics_summary: diagnostics_summary,
          endpoint_closed: endpoint.is_closed
        )
      ensure
        close_endpoint(endpoint)
      end

      def skipped_result
        Result.new(
          mode: "skipped",
          live: false,
          skip_reason: LIVE_SKIP_REASON,
          client_constructed: false,
          ping_attempted: false,
          metrics_pushed: false,
          diagnostics_attempted: false,
          diagnostics_sent: false
        )
      end

      def bind_dry_endpoint
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0"
          )
        )
      end

      def bind_live_endpoint
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_n0,
            bind_addr: "0.0.0.0:0"
          )
        )
      end

      def live_requested?(env)
        env["IROH_SERVICES_LIVE"] == "1"
      end

      def send_requested?(env)
        live_requested?(env) && env["IROH_SERVICES_SEND"] == "1"
      end

      def close_endpoint(endpoint)
        LoopbackSupport.close_endpoint(endpoint)
      end

      def with_deadline_timeout(deadline, message)
        LoopbackSupport.with_deadline_timeout(deadline, message) { yield }
      end

      def normalize_timeout_seconds(timeout)
        LoopbackSupport.normalize_timeout_seconds(timeout)
      end

      def monotonic_time
        LoopbackSupport.monotonic_time
      end
    end
  end
end
