# frozen_string_literal: true

require "thread"
require "timeout"
require "iroh"

module Iroh
  module Examples
    module PostcardDemo
      ALPN = "iroh-ruby/demo/postcard"
      DEFAULT_MESSAGE = "hello from ruby iroh"
      DEFAULT_TIMEOUT_SECONDS = 10
      MAX_PAYLOAD_BYTES = 1_048_576

      Result = Struct.new(
        :sender_id,
        :receiver_id,
        :alpn,
        :payload,
        :sender_closed,
        :receiver_closed,
        keyword_init: true
      )

      module_function

      def deliver(message = DEFAULT_MESSAGE, timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        message = normalize_message(message)
        receiver = with_deadline_timeout(deadline, "timed out binding postcard receiver endpoint") do
          bind_endpoint
        end
        sender = with_deadline_timeout(deadline, "timed out binding postcard sender endpoint") do
          bind_endpoint
        end
        receiver_queue = Queue.new

        receiver_thread = Thread.new do
          receive_one_message(receiver, receiver_queue)
        end

        sender_connection = with_deadline_timeout(deadline, "timed out connecting postcard sender") do
          sender.connect(receiver.addr, ALPN)
        end
        send_stream = with_deadline_timeout(deadline, "timed out opening postcard send stream") do
          sender_connection.open_uni
        end
        with_deadline_timeout(deadline, "timed out writing postcard payload") do
          send_stream.write_all(message)
        end
        with_deadline_timeout(deadline, "timed out finishing postcard send stream") do
          send_stream.finish
        end

        status, value = wait_for_receiver_result(receiver_queue, deadline)
        wait_for_receiver_thread(receiver_thread, deadline)
        raise value if status == :error

        sender_id = sender.id.to_s
        receiver_id = receiver.id.to_s

        close_endpoint(sender)
        close_endpoint(receiver)

        Result.new(
          sender_id: sender_id,
          receiver_id: receiver_id,
          alpn: ALPN,
          payload: value,
          sender_closed: sender.is_closed,
          receiver_closed: receiver.is_closed
        )
      ensure
        close_endpoint(sender)
        close_endpoint(receiver)
        cleanup_receiver_thread(receiver_thread)
      end

      def bind_endpoint
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0",
            alpns: [ALPN]
          )
        )
      end

      def receive_one_message(receiver, receiver_queue)
        incoming = receiver.accept_next
        raise "receiver endpoint closed before accepting a connection" unless incoming

        accepting = incoming.accept
        receiver_connection = accepting.connect
        recv_stream = receiver_connection.accept_uni
        payload = recv_stream.read_to_end(MAX_PAYLOAD_BYTES)

        receiver_queue << [:ok, normalize_payload(payload)]
      rescue StandardError => e
        receiver_queue << [:error, e]
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

      def wait_for_receiver_result(receiver_queue, deadline)
        timeout_seconds = remaining_timeout(
          deadline,
          "timed out waiting for postcard receiver"
        )
        Timeout.timeout(timeout_seconds, Timeout::Error,
                        "timed out waiting for postcard receiver after #{format_timeout_seconds(timeout_seconds)} seconds") do
          receiver_queue.pop
        end
      end

      def wait_for_receiver_thread(receiver_thread, deadline)
        return if receiver_thread.join(0)

        timeout_seconds = remaining_timeout(
          deadline,
          "timed out waiting for postcard receiver thread"
        )
        return if receiver_thread.join(timeout_seconds)

        raise Timeout::Error,
              "timed out waiting for postcard receiver thread after #{format_timeout_seconds(timeout_seconds)} seconds"
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
