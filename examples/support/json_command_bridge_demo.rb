# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"

require_relative "loopback_support"

module Iroh
  module Examples
    module JsonCommandBridgeDemo
      ALPN = "iroh-ruby/demo/json-command-bridge"
      DEFAULT_MESSAGE = "hello from json bridge"
      DEFAULT_TIMEOUT_SECONDS = 15
      MAX_PAYLOAD_BYTES = 1_048_576
      MAX_COMMANDS = 16
      SERVER_SCRIPT_PATH = File.expand_path("../json_command_server.rb", __dir__)
      CLIENT_SCRIPT_PATH = File.expand_path("../json_command_client.rb", __dir__)

      module_function

      def default_commands(message = DEFAULT_MESSAGE)
        message = normalize_message(message)
        [
          { "request_id" => "1", "op" => "echo", "params" => { "message" => message } },
          { "request_id" => "2", "op" => "identify" },
          { "request_id" => "3", "op" => "stats" },
          { "request_id" => "4", "op" => "does-not-exist" },
          { "request_id" => "5", "op" => "shutdown" }
        ]
      end

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

      def response_for(command, context)
        command = stringify_keys(command)
        request_id = command["request_id"]
        op = command["op"].to_s

        case op
        when "echo"
          ok_response(request_id, op, "message" => command.dig("params", "message").to_s)
        when "identify"
          ok_response(
            request_id,
            op,
            "server_id" => context.fetch(:server_id),
            "remote_id" => context.fetch(:remote_id),
            "alpn" => ALPN
          )
        when "stats"
          ok_response(
            request_id,
            op,
            "handled_commands" => context.fetch(:handled_commands),
            "connection_stable_id" => context.fetch(:connection_stable_id),
            "paths" => context.fetch(:paths)
          )
        when "shutdown"
          ok_response(request_id, op, "shutdown" => true)
        else
          error_response(request_id, op, "unsupported command: #{op}")
        end
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

      def response_lines(stdout)
        stdout.each_line.filter_map do |line|
          next unless line.start_with?("response: ")

          decode_response(line.sub(/\Aresponse:\s*/, ""))
        end
      end

      def run_process_demo(message = DEFAULT_MESSAGE, timeout: DEFAULT_TIMEOUT_SECONDS)
        timeout_seconds = normalize_timeout_seconds(timeout)
        deadline = monotonic_time + timeout_seconds
        server_stdin = nil
        server_stdout = nil
        server_stderr = nil
        server_wait = nil
        server_err_reader = nil

        begin
          server_stdin, server_stdout, server_stderr, server_wait = Open3.popen3(
            RbConfig.ruby,
            SERVER_SCRIPT_PATH
          )
          server_stdin.close
          server_err_reader = Thread.new { server_stderr.read }
          ticket_line = with_deadline_timeout(deadline, "timed out waiting for JSON command bridge server") do
            loop do
              line = server_stdout.gets
              raise "JSON command bridge server exited before printing a ticket" unless line

              line = line.chomp
              break line if line.start_with?("ticket: ")
            end
          end
          ticket = ticket_line.sub(/\Aticket:\s*/, "")
          message = normalize_message(message)

          client_stdout, client_stderr, client_status = with_deadline_timeout(
            deadline,
            "timed out running JSON command bridge client"
          ) do
            Open3.capture3(
              RbConfig.ruby,
              CLIENT_SCRIPT_PATH,
              ticket,
              message
            )
          end

          server_stdout_tail = with_deadline_timeout(
            deadline,
            "timed out waiting for JSON command bridge server exit"
          ) do
            server_stdout.read
          end
          server_status = server_wait.value
          server_stderr_text = server_err_reader.value

          raise client_stderr unless client_status.success?
          raise server_stderr_text unless server_status.success?

          ProcessResult.new(
            ticket: ticket,
            message: message,
            client_stdout: client_stdout,
            server_stdout: server_stdout_tail,
            responses: response_lines(client_stdout)
          )
        ensure
          [server_stdin, server_stdout, server_stderr].each do |io|
            io&.close unless io&.closed?
          rescue IOError
            nil
          end
          if server_wait&.alive?
            Process.kill("TERM", server_wait.pid)
            server_wait.value
          end
        end
      end

      ProcessResult = Struct.new(
        :ticket,
        :message,
        :client_stdout,
        :server_stdout,
        :responses,
        keyword_init: true
      )

      module Server
        Result = Struct.new(
          :server_id,
          :ticket,
          :alpn,
          :responses,
          :handled_commands,
          :server_closed,
          keyword_init: true
        )

        module_function

        def run_once(timeout: JsonCommandBridgeDemo::DEFAULT_TIMEOUT_SECONDS, out: $stdout)
          timeout_seconds = JsonCommandBridgeDemo.normalize_timeout_seconds(timeout)
          deadline = JsonCommandBridgeDemo.monotonic_time + timeout_seconds
          server = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out binding JSON command server endpoint") do
            JsonCommandBridgeDemo.bind_endpoint
          end
          server_id = server.id.to_s
          ticket = Iroh::EndpointTicket.from_addr(server.addr).to_s

          out.puts "ticket: #{ticket}"
          out.flush if out.respond_to?(:flush)

          incoming = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out waiting for JSON command client") do
            server.accept_next
          end
          raise "server endpoint closed before accepting a connection" unless incoming

          accepting = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out accepting JSON command client") do
            incoming.accept
          end
          connection = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out establishing JSON command connection") do
            accepting.connect
          end

          responses = handle_connection(server, connection, deadline)
          JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out waiting for JSON command client close") do
            connection.closed
          end
          JsonCommandBridgeDemo.close_endpoint(server)

          Result.new(
            server_id: server_id,
            ticket: ticket,
            alpn: JsonCommandBridgeDemo::ALPN,
            responses: responses,
            handled_commands: responses.length,
            server_closed: server.is_closed
          )
        ensure
          JsonCommandBridgeDemo.close_endpoint(server)
        end

        def handle_connection(server, connection, deadline)
          responses = []

          JsonCommandBridgeDemo::MAX_COMMANDS.times do
            stream = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out accepting JSON command stream") do
              connection.accept_bi
            end
            payload = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out reading JSON command") do
              stream.recv.read_to_end(JsonCommandBridgeDemo::MAX_PAYLOAD_BYTES)
            end
            response = response_for_payload(
              payload,
              server: server,
              connection: connection,
              handled_commands: responses.length + 1
            )
            JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out writing JSON command response") do
              stream.send.write_all(JsonCommandBridgeDemo.encode_response(response))
            end
            JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out finishing JSON command response") do
              stream.send.finish
            end

            responses << response
            break if JsonCommandBridgeDemo.shutdown_response?(response)
          end

          responses
        end

        def response_for_payload(payload, server:, connection:, handled_commands:)
          command = JsonCommandBridgeDemo.decode_command(payload)
          JsonCommandBridgeDemo.response_for(
            command,
            server_id: server.id.to_s,
            remote_id: connection.remote_id.to_s,
            handled_commands: handled_commands,
            connection_stable_id: connection.stable_id,
            paths: connection.paths.length
          )
        rescue JSON::ParserError, ArgumentError => e
          JsonCommandBridgeDemo.error_response(nil, "invalid", e.message)
        end
      end

      module Client
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

        module_function

        def deliver(ticket, commands = JsonCommandBridgeDemo.default_commands,
                    timeout: JsonCommandBridgeDemo::DEFAULT_TIMEOUT_SECONDS)
          timeout_seconds = JsonCommandBridgeDemo.normalize_timeout_seconds(timeout)
          deadline = JsonCommandBridgeDemo.monotonic_time + timeout_seconds
          ticket = JsonCommandBridgeDemo.normalize_ticket(ticket)
          commands = commands.map { |command| JsonCommandBridgeDemo.stringify_keys(command) }
          parsed_addr = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out parsing JSON command ticket") do
            Iroh::EndpointTicket.from_string(ticket).endpoint_addr
          end
          sender = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out binding JSON command client endpoint") do
            JsonCommandBridgeDemo.bind_endpoint
          end
          sender_id = sender.id.to_s
          receiver_id = parsed_addr.id.to_s
          connection = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out connecting JSON command client") do
            sender.connect(parsed_addr, JsonCommandBridgeDemo::ALPN)
          end
          responses = commands.map do |command|
            send_command(connection, command, deadline)
          end

          JsonCommandBridgeDemo.close_endpoint(sender)

          Result.new(
            sender_id: sender_id,
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: JsonCommandBridgeDemo::ALPN,
            commands: commands,
            responses: responses,
            sender_closed: sender.is_closed
          )
        ensure
          JsonCommandBridgeDemo.close_endpoint(sender)
        end

        def send_command(connection, command, deadline)
          stream = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out opening JSON command stream") do
            connection.open_bi
          end
          JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out writing JSON command") do
            stream.send.write_all(JsonCommandBridgeDemo.encode_command(command))
          end
          JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out finishing JSON command") do
            stream.send.finish
          end
          payload = JsonCommandBridgeDemo.with_deadline_timeout(deadline, "timed out reading JSON command response") do
            stream.recv.read_to_end(JsonCommandBridgeDemo::MAX_PAYLOAD_BYTES)
          end

          JsonCommandBridgeDemo.decode_response(payload)
        end
      end
    end
  end
end
