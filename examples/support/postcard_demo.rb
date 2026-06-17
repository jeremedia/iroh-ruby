# frozen_string_literal: true

require "thread"
require_relative "loopback_support"

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
        LoopbackSupport.bind_endpoint(ALPN)
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
        LoopbackSupport.normalize_message(message)
      end

      def normalize_payload(payload)
        LoopbackSupport.normalize_payload(payload)
      end

      def close_endpoint(endpoint)
        LoopbackSupport.close_endpoint(endpoint)
      end

      def wait_for_receiver_result(receiver_queue, deadline)
        LoopbackSupport.wait_for_receiver_result(receiver_queue, deadline, label: "postcard")
      end

      def wait_for_receiver_thread(receiver_thread, deadline)
        LoopbackSupport.wait_for_receiver_thread(receiver_thread, deadline, label: "postcard")
      end

      def cleanup_receiver_thread(receiver_thread)
        LoopbackSupport.cleanup_receiver_thread(receiver_thread)
      end

      def with_deadline_timeout(deadline, message)
        LoopbackSupport.with_deadline_timeout(deadline, message) { yield }
      end

      def remaining_timeout(deadline, message)
        LoopbackSupport.remaining_timeout(deadline, message)
      end

      def normalize_timeout_seconds(timeout)
        LoopbackSupport.normalize_timeout_seconds(timeout)
      end

      def format_timeout_seconds(seconds)
        LoopbackSupport.format_timeout_seconds(seconds)
      end

      def monotonic_time
        LoopbackSupport.monotonic_time
      end
    end
  end
end
