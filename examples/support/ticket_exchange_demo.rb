# frozen_string_literal: true

require_relative "loopback_support"

module Iroh
  module Examples
    module TicketExchangeDemo
      ALPN = "iroh-ruby/demo/ticket-exchange"
      DEFAULT_MESSAGE = "hello from another ruby process"
      DEFAULT_TIMEOUT_SECONDS = 10
      MAX_PAYLOAD_BYTES = 1_048_576

      module_function

      def normalize_ticket(ticket)
        ticket.to_s.strip.tap do |value|
          raise ArgumentError, "ticket is required" if value.empty?
        end
      end

      def normalize_message(message)
        LoopbackSupport.normalize_message(message)
      end

      def normalize_payload(payload)
        LoopbackSupport.normalize_payload(payload)
      end

      def bind_endpoint
        LoopbackSupport.bind_endpoint(ALPN)
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

      module Server
        Result = Struct.new(
          :receiver_id,
          :ticket,
          :alpn,
          :received,
          :sent,
          :receiver_closed,
          keyword_init: true
        )

        module_function

        def run_once(timeout: TicketExchangeDemo::DEFAULT_TIMEOUT_SECONDS, out: $stdout)
          timeout_seconds = TicketExchangeDemo.normalize_timeout_seconds(timeout)
          deadline = TicketExchangeDemo.monotonic_time + timeout_seconds
          receiver = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out binding ticket exchange server endpoint") do
            TicketExchangeDemo.bind_endpoint
          end
          receiver_id = receiver.id.to_s
          ticket = Iroh::EndpointTicket.from_addr(receiver.addr).to_s

          out.puts "ticket: #{ticket}"
          out.flush if out.respond_to?(:flush)

          incoming = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out waiting for ticket exchange client") do
            receiver.accept_next
          end
          raise "server endpoint closed before accepting a connection" unless incoming

          accepting = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out accepting ticket exchange client") do
            incoming.accept
          end
          receiver_connection = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out establishing ticket exchange server connection") do
            accepting.connect
          end
          receiver_stream = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out accepting ticket exchange stream") do
            receiver_connection.accept_bi
          end
          received = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out reading ticket exchange request") do
            TicketExchangeDemo.normalize_payload(receiver_stream.recv.read_to_end(TicketExchangeDemo::MAX_PAYLOAD_BYTES))
          end
          response = TicketExchangeDemo.normalize_message("echo: #{received}")

          TicketExchangeDemo.with_deadline_timeout(deadline, "timed out writing ticket exchange response") do
            receiver_stream.send.write_all(response)
          end
          TicketExchangeDemo.with_deadline_timeout(deadline, "timed out finishing ticket exchange response") do
            receiver_stream.send.finish
          end
          TicketExchangeDemo.with_deadline_timeout(deadline, "timed out waiting for ticket exchange client close") do
            receiver_connection.closed
          end

          TicketExchangeDemo.close_endpoint(receiver)

          Result.new(
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: TicketExchangeDemo::ALPN,
            received: received,
            sent: response,
            receiver_closed: receiver.is_closed
          )
        ensure
          TicketExchangeDemo.close_endpoint(receiver)
        end
      end

      module Client
        Result = Struct.new(
          :sender_id,
          :receiver_id,
          :ticket,
          :alpn,
          :sent,
          :received,
          :sender_closed,
          keyword_init: true
        )

        module_function

        def deliver(ticket, message = TicketExchangeDemo::DEFAULT_MESSAGE, timeout: TicketExchangeDemo::DEFAULT_TIMEOUT_SECONDS)
          timeout_seconds = TicketExchangeDemo.normalize_timeout_seconds(timeout)
          deadline = TicketExchangeDemo.monotonic_time + timeout_seconds
          ticket = TicketExchangeDemo.normalize_ticket(ticket)
          message = TicketExchangeDemo.normalize_message(message)
          parsed_addr = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out parsing ticket exchange endpoint ticket") do
            Iroh::EndpointTicket.from_string(ticket).endpoint_addr
          end
          sender = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out binding ticket exchange client endpoint") do
            TicketExchangeDemo.bind_endpoint
          end
          sender_id = sender.id.to_s
          receiver_id = parsed_addr.id.to_s

          sender_connection = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out connecting ticket exchange client") do
            sender.connect(parsed_addr, TicketExchangeDemo::ALPN)
          end
          sender_stream = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out opening ticket exchange bidirectional stream") do
            sender_connection.open_bi
          end

          TicketExchangeDemo.with_deadline_timeout(deadline, "timed out writing ticket exchange request") do
            sender_stream.send.write_all(message)
          end
          TicketExchangeDemo.with_deadline_timeout(deadline, "timed out finishing ticket exchange request") do
            sender_stream.send.finish
          end

          received = TicketExchangeDemo.with_deadline_timeout(deadline, "timed out reading ticket exchange response") do
            TicketExchangeDemo.normalize_payload(sender_stream.recv.read_to_end(TicketExchangeDemo::MAX_PAYLOAD_BYTES))
          end

          TicketExchangeDemo.close_endpoint(sender)

          Result.new(
            sender_id: sender_id,
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: TicketExchangeDemo::ALPN,
            sent: message,
            received: received,
            sender_closed: sender.is_closed
          )
        ensure
          TicketExchangeDemo.close_endpoint(sender)
        end
      end
    end
  end
end
