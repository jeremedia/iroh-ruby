# frozen_string_literal: true

require_relative "loopback_support"

module Iroh
  module Examples
    module ProtocolRouterDemo
      ALPN = "iroh-ruby/demo/protocol-router"
      WRONG_ALPN = "iroh-ruby/demo/protocol-router-wrong"
      DEFAULT_MESSAGE = "hello from the protocol router"
      DEFAULT_TIMEOUT_SECONDS = 10
      RESPONSE_PREFIX = "routed: "
      MAX_PAYLOAD_BYTES = 1_048_576

      Result = Struct.new(
        :server_id,
        :client_id,
        :ticket,
        :alpn,
        :sent,
        :received,
        :created_count,
        :accepted_count,
        :shutdown_count,
        :last_received,
        :last_sent,
        :last_error,
        :server_closed,
        :client_closed,
        keyword_init: true
      )

      module_function

      def run_once(message = DEFAULT_MESSAGE, timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        message = normalize_message(message)
        recorder = Iroh::ProtocolRouterEchoRecorder.with_response_prefix(RESPONSE_PREFIX)
        server = bind_router_endpoint(recorder)
        client = bind_client_endpoint
        ticket = Iroh::EndpointTicket.from_addr(server.addr).to_s
        server_id = server.id.to_s
        client_id = client.id.to_s
        server_addr = Iroh::EndpointTicket.from_string(ticket).endpoint_addr

        connection = with_deadline_timeout(deadline, "timed out connecting protocol router client") do
          client.connect(server_addr, ALPN)
        end
        stream = with_deadline_timeout(deadline, "timed out opening protocol router stream") do
          connection.open_bi
        end
        with_deadline_timeout(deadline, "timed out writing protocol router request") do
          stream.send.write_all(message)
        end
        with_deadline_timeout(deadline, "timed out finishing protocol router request") do
          stream.send.finish
        end
        received = with_deadline_timeout(deadline, "timed out reading protocol router response") do
          normalize_payload(stream.recv.read_to_end(MAX_PAYLOAD_BYTES))
        end

        close_endpoint(client)
        close_endpoint(server)

        Result.new(
          server_id: server_id,
          client_id: client_id,
          ticket: ticket,
          alpn: ALPN,
          sent: message,
          received: received,
          created_count: recorder.created_count,
          accepted_count: recorder.accepted_count,
          shutdown_count: recorder.shutdown_count,
          last_received: recorder.last_received,
          last_sent: recorder.last_sent,
          last_error: recorder.last_error,
          server_closed: server.is_closed,
          client_closed: client.is_closed
        )
      ensure
        close_endpoint(client)
        close_endpoint(server)
      end

      def reject_wrong_alpn(timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        recorder = Iroh::ProtocolRouterEchoRecorder.with_response_prefix(RESPONSE_PREFIX)
        server = bind_router_endpoint(recorder)
        client = bind_client_endpoint(WRONG_ALPN)
        ticket = Iroh::EndpointTicket.from_addr(server.addr).to_s
        server_addr = Iroh::EndpointTicket.from_string(ticket).endpoint_addr

        with_deadline_timeout(deadline, "timed out attempting wrong ALPN connection") do
          client.connect(server_addr, WRONG_ALPN)
        end
        raise "wrong ALPN connection unexpectedly succeeded"
      rescue StandardError => e
        e
      ensure
        close_endpoint(client)
        close_endpoint(server)
      end

      def bind_router_endpoint(recorder)
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0",
            protocols: { ALPN => recorder.creator }
          )
        )
      end

      def bind_client_endpoint(alpn = ALPN)
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0",
            alpns: [alpn]
          )
        )
      end

      def normalize_message(message)
        LoopbackSupport.normalize_message(message)
      end

      def normalize_payload(payload)
        LoopbackSupport.normalize_payload(payload)
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
