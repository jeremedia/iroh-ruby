# frozen_string_literal: true

require "json"
require "timeout"

module Iroh
  module JsonBridge
    DEFAULT_TIMEOUT_SECONDS = 15
    MAX_PAYLOAD_BYTES = 1_048_576
    MAX_COMMANDS = 16

    module_function

    def encode_command(command)
      JSON.generate(stringify_keys(command))
    end

    def decode_command(payload)
      decoded = JSON.parse(normalize_payload(payload))
      raise ArgumentError, "JSON command must be an object" unless decoded.is_a?(Hash)

      decoded
    end

    def encode_response(response)
      JSON.generate(stringify_keys(response))
    end

    def decode_response(payload)
      decoded = JSON.parse(normalize_payload(payload))
      raise ArgumentError, "JSON response must be an object" unless decoded.is_a?(Hash)

      decoded
    end

    def ok_response(request_id, op, result)
      {
        "ok" => true,
        "request_id" => request_id,
        "op" => op,
        "result" => result
      }
    end

    def error_response(request_id, op, error)
      {
        "ok" => false,
        "request_id" => request_id,
        "op" => op,
        "error" => error
      }
    end

    def shutdown_response?(response)
      response["ok"] && response["op"] == "shutdown" && response.dig("result", "shutdown")
    end

    def normalize_ticket(ticket)
      ticket.to_s.strip.tap do |value|
        raise ArgumentError, "ticket is required" if value.empty?
      end
    end

    def normalize_message(message)
      message.to_s.encode(Encoding::UTF_8)
    end

    def normalize_payload(payload)
      payload = payload.to_s.dup
      payload.force_encoding(Encoding::UTF_8)
      payload
    end

    def normalize_timeout_seconds(timeout)
      seconds = Float(timeout)
      raise ArgumentError, "timeout must be positive" unless seconds.positive?

      seconds
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

    def format_timeout_seconds(seconds)
      seconds == seconds.to_i ? seconds.to_i.to_s : seconds.to_s
    end

    def stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), memo|
          memo[key.to_s] = stringify_keys(child)
        end
      when Array
        value.map { |child| stringify_keys(child) }
      else
        value
      end
    end

    def close_endpoint(endpoint)
      return unless endpoint
      return if endpoint.is_closed

      endpoint.close
    rescue StandardError
      nil
    end

    private_class_method :normalize_timeout_seconds,
                         :monotonic_time,
                         :with_deadline_timeout,
                         :remaining_timeout,
                         :format_timeout_seconds,
                         :stringify_keys,
                         :close_endpoint

    class CommandRouter
      def initialize
        @handlers = {}
      end

      def on(op, &handler)
        raise ArgumentError, "handler block is required" unless handler

        @handlers[op.to_s] = handler
        self
      end

      def call(command, context = {})
        command = JsonBridge.__send__(:stringify_keys, command)
        return JsonBridge.error_response(nil, "invalid", "JSON command must be an object") unless command.is_a?(Hash)

        request_id = command["request_id"]
        op = command["op"].to_s
        handler = @handlers[op]
        return JsonBridge.error_response(request_id, op, "unsupported command: #{op}") unless handler

        JsonBridge.ok_response(request_id, op, handler.call(command, context) || {})
      rescue StandardError => e
        JsonBridge.error_response(request_id, op, "handler failed: #{e.message}")
      end
    end

    class Server
      Result = Struct.new(
        :server_id,
        :ticket,
        :alpn,
        :responses,
        :handled_commands,
        :server_closed,
        keyword_init: true
      )

      def initialize(endpoint_options:, alpn:, router:, timeout: JsonBridge::DEFAULT_TIMEOUT_SECONDS,
                     max_payload_bytes: JsonBridge::MAX_PAYLOAD_BYTES,
                     max_commands: JsonBridge::MAX_COMMANDS,
                     context: {},
                     stop_when: JsonBridge.method(:shutdown_response?))
        raise ArgumentError, "endpoint_options is required" unless endpoint_options
        raise ArgumentError, "alpn is required" if alpn.to_s.empty?
        raise ArgumentError, "router is required" unless router

        @endpoint_options = endpoint_options
        @alpn = alpn
        @router = router
        @timeout = timeout
        @max_payload_bytes = max_payload_bytes
        @max_commands = max_commands
        @context = context
        @stop_when = stop_when
      end

      def run_once(out: nil)
        timeout_seconds = JsonBridge.__send__(:normalize_timeout_seconds, @timeout)
        deadline = JsonBridge.__send__(:monotonic_time) + timeout_seconds
        server = nil

        begin
          server = JsonBridge.__send__(
            :with_deadline_timeout,
            deadline,
            "timed out binding JSON bridge server endpoint"
          ) do
            Iroh::Endpoint.bind(@endpoint_options)
          end
          server_id = server.id.to_s
          ticket = Iroh::EndpointTicket.from_addr(server.addr).to_s

          out&.puts "ticket: #{ticket}"
          out&.flush if out.respond_to?(:flush)

          connection = accept_connection(server, deadline)
          responses = handle_connection(server, connection, deadline)
          JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out waiting for JSON bridge client close") do
            connection.closed
          end
          JsonBridge.__send__(:close_endpoint, server)

          Result.new(
            server_id: server_id,
            ticket: ticket,
            alpn: @alpn,
            responses: responses,
            handled_commands: responses.length,
            server_closed: server.is_closed
          )
        ensure
          JsonBridge.__send__(:close_endpoint, server)
        end
      end

      private

      def accept_connection(server, deadline)
        incoming = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out waiting for JSON bridge client") do
          server.accept_next
        end
        raise "JSON bridge server endpoint closed before accepting a connection" unless incoming

        accepting = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out accepting JSON bridge client") do
          incoming.accept
        end
        JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out establishing JSON bridge connection") do
          accepting.connect
        end
      end

      def handle_connection(server, connection, deadline)
        responses = []

        @max_commands.times do
          stream = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out accepting JSON bridge stream") do
            connection.accept_bi
          end
          payload = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out reading JSON bridge command") do
            stream.recv.read_to_end(@max_payload_bytes)
          end
          response = response_for_payload(
            payload,
            server: server,
            connection: connection,
            handled_commands: responses.length + 1
          )
          JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out writing JSON bridge response") do
            stream.send.write_all(JsonBridge.encode_response(response))
          end
          JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out finishing JSON bridge response") do
            stream.send.finish
          end

          responses << response
          break if @stop_when&.call(response)
        end

        responses
      end

      def response_for_payload(payload, server:, connection:, handled_commands:)
        command = JsonBridge.decode_command(payload)
        @router.call(command, command_context(server, connection, handled_commands))
      rescue JSON::ParserError, ArgumentError => e
        JsonBridge.error_response(nil, "invalid", e.message)
      end

      def command_context(server, connection, handled_commands)
        @context.merge(
          server_id: server.id.to_s,
          remote_id: connection.remote_id.to_s,
          handled_commands: handled_commands,
          connection_stable_id: connection.stable_id,
          paths: connection.paths.length
        )
      end
    end

    class Client
      Result = Struct.new(
        :sender_id,
        :receiver_id,
        :ticket,
        :alpn,
        :commands,
        :responses,
        :sender_closed,
        keyword_init: true
      )

      def initialize(endpoint_options:, alpn:, timeout: JsonBridge::DEFAULT_TIMEOUT_SECONDS,
                     max_payload_bytes: JsonBridge::MAX_PAYLOAD_BYTES)
        raise ArgumentError, "endpoint_options is required" unless endpoint_options
        raise ArgumentError, "alpn is required" if alpn.to_s.empty?

        @endpoint_options = endpoint_options
        @alpn = alpn
        @timeout = timeout
        @max_payload_bytes = max_payload_bytes
      end

      def deliver(ticket, commands)
        timeout_seconds = JsonBridge.__send__(:normalize_timeout_seconds, @timeout)
        deadline = JsonBridge.__send__(:monotonic_time) + timeout_seconds
        ticket = JsonBridge.normalize_ticket(ticket)
        commands = commands.map { |command| JsonBridge.__send__(:stringify_keys, command) }
        sender = nil

        begin
          parsed_addr = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out parsing JSON bridge ticket") do
            Iroh::EndpointTicket.from_string(ticket).endpoint_addr
          end
          sender = JsonBridge.__send__(
            :with_deadline_timeout,
            deadline,
            "timed out binding JSON bridge client endpoint"
          ) do
            Iroh::Endpoint.bind(@endpoint_options)
          end
          sender_id = sender.id.to_s
          receiver_id = parsed_addr.id.to_s
          connection = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out connecting JSON bridge client") do
            sender.connect(parsed_addr, @alpn)
          end
          responses = commands.map do |command|
            send_command(connection, command, deadline)
          end

          JsonBridge.__send__(:close_endpoint, sender)

          Result.new(
            sender_id: sender_id,
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: @alpn,
            commands: commands,
            responses: responses,
            sender_closed: sender.is_closed
          )
        ensure
          JsonBridge.__send__(:close_endpoint, sender)
        end
      end

      private

      def send_command(connection, command, deadline)
        stream = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out opening JSON bridge stream") do
          connection.open_bi
        end
        JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out writing JSON bridge command") do
          stream.send.write_all(JsonBridge.encode_command(command))
        end
        JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out finishing JSON bridge command") do
          stream.send.finish
        end
        payload = JsonBridge.__send__(:with_deadline_timeout, deadline, "timed out reading JSON bridge response") do
          stream.recv.read_to_end(@max_payload_bytes)
        end

        JsonBridge.decode_response(payload)
      end
    end
  end
end
