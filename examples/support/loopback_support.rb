# frozen_string_literal: true

require "timeout"
require "iroh"

module Iroh
  module Examples
    module LoopbackSupport
      module_function

      def bind_endpoint(alpn)
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
        message.to_s.encode(Encoding::UTF_8)
      end

      def normalize_payload(payload)
        payload = payload.to_s
        payload.force_encoding(Encoding::UTF_8)
        payload
      end

      def close_endpoint(endpoint)
        return unless endpoint
        return if endpoint.is_closed

        endpoint.close
      rescue StandardError
        nil
      end

      def wait_for_receiver_result(receiver_queue, deadline, label:)
        timeout_seconds = remaining_timeout(
          deadline,
          "timed out waiting for #{label} receiver"
        )
        Timeout.timeout(timeout_seconds, Timeout::Error,
                        "timed out waiting for #{label} receiver after #{format_timeout_seconds(timeout_seconds)} seconds") do
          receiver_queue.pop
        end
      end

      def wait_for_receiver_thread(receiver_thread, deadline, label:)
        return if receiver_thread.join(0)

        timeout_seconds = remaining_timeout(
          deadline,
          "timed out waiting for #{label} receiver thread"
        )
        return if receiver_thread.join(timeout_seconds)

        raise Timeout::Error,
              "timed out waiting for #{label} receiver thread after #{format_timeout_seconds(timeout_seconds)} seconds"
      end

      def cleanup_receiver_thread(receiver_thread)
        return unless receiver_thread
        return unless receiver_thread.alive?

        receiver_thread.join(0.25)
        return unless receiver_thread.alive?

        receiver_thread.kill
        receiver_thread.join(0.25)
      end

      def with_deadline_timeout(deadline, message)
        timeout_seconds = remaining_timeout(deadline, message)
        Timeout.timeout(timeout_seconds, Timeout::Error,
                        "#{message} after #{format_timeout_seconds(timeout_seconds)} seconds") do
          yield
        end
      end

      def remaining_timeout(deadline, message)
        remaining = deadline - monotonic_time
        return remaining if remaining.positive?

        raise Timeout::Error, message
      end

      def normalize_timeout_seconds(timeout)
        seconds = Float(timeout)
        raise ArgumentError, "timeout must be positive" unless seconds.positive?

        seconds
      end

      def format_timeout_seconds(seconds)
        seconds == seconds.to_i ? seconds.to_i.to_s : seconds.to_s
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
