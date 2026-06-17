# frozen_string_literal: true

require "thread"
require_relative "loopback_support"

module Iroh
  module Examples
    module TicketEchoDemo
      ALPN = "iroh-ruby/demo/ticket-echo"
      DEFAULT_MESSAGE = "hello from ticket land"
      DEFAULT_TIMEOUT_SECONDS = 10
      MAX_PAYLOAD_BYTES = 1_048_576

      Result = Struct.new(
        :sender_id,
        :receiver_id,
        :ticket,
        :alpn,
        :sent,
        :received,
        :sender_closed,
        :receiver_closed,
        keyword_init: true
      )

      module_function

      def deliver(message = DEFAULT_MESSAGE, timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        message = normalize_message(message)
        receiver = with_deadline_timeout(deadline, "timed out binding ticket echo receiver endpoint") do
          bind_endpoint
        end
        sender = with_deadline_timeout(deadline, "timed out binding ticket echo sender endpoint") do
          bind_endpoint
        end
        receiver_queue = Queue.new
        ticket = Iroh::EndpointTicket.from_addr(receiver.addr).to_s

        receiver_thread = Thread.new do
          receive_one_echo(receiver, receiver_queue)
        end

        parsed_addr = with_deadline_timeout(deadline, "timed out parsing ticket echo endpoint ticket") do
          Iroh::EndpointTicket.from_string(ticket).endpoint_addr
        end
        sender_connection = with_deadline_timeout(deadline, "timed out connecting ticket echo sender") do
          sender.connect(parsed_addr, ALPN)
        end
        sender_stream = with_deadline_timeout(deadline, "timed out opening ticket echo bidirectional stream") do
          sender_connection.open_bi
        end

        with_deadline_timeout(deadline, "timed out writing ticket echo request") do
          sender_stream.send.write_all(message)
        end
        with_deadline_timeout(deadline, "timed out finishing ticket echo request") do
          sender_stream.send.finish
        end

        received = with_deadline_timeout(deadline, "timed out reading ticket echo response") do
          normalize_payload(sender_stream.recv.read_to_end(MAX_PAYLOAD_BYTES))
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
          ticket: ticket,
          alpn: ALPN,
          sent: message,
          received: received,
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

      def receive_one_echo(receiver, receiver_queue)
        incoming = receiver.accept_next
        raise "receiver endpoint closed before accepting a connection" unless incoming

        accepting = incoming.accept
        receiver_connection = accepting.connect
        receiver_stream = receiver_connection.accept_bi
        payload = normalize_payload(receiver_stream.recv.read_to_end(MAX_PAYLOAD_BYTES))
        response = normalize_message("echo: #{payload}")

        receiver_stream.send.write_all(response)
        receiver_stream.send.finish

        receiver_queue << [:ok, payload]
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
        LoopbackSupport.wait_for_receiver_result(receiver_queue, deadline, label: "ticket echo")
      end

      def wait_for_receiver_thread(receiver_thread, deadline)
        LoopbackSupport.wait_for_receiver_thread(receiver_thread, deadline, label: "ticket echo")
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
