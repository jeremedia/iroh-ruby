# frozen_string_literal: true

require "open3"
require "rbconfig"

require_relative "json_command_bridge_demo"

module Iroh
  module Examples
    module RailsPairDemo
      ALPN = "iroh-ruby/demo/rails-pair"
      DEFAULT_MESSAGE = "hello from rails pair"
      DEFAULT_TIMEOUT_SECONDS = 20
      SERVER_BIN_PATH = File.expand_path("../rails_pair/server_app/bin/rails", __dir__)
      CLIENT_BIN_PATH = File.expand_path("../rails_pair/client_app/bin/rails", __dir__)

      module_function

      def default_commands(message = DEFAULT_MESSAGE)
        JsonCommandBridgeDemo.default_commands(message)
      end

      def normalize_ticket(ticket)
        JsonCommandBridgeDemo.normalize_ticket(ticket)
      end

      def normalize_message(message)
        JsonCommandBridgeDemo.normalize_message(message)
      end

      def normalize_timeout_seconds(timeout)
        JsonCommandBridgeDemo.normalize_timeout_seconds(timeout)
      end

      def monotonic_time
        JsonCommandBridgeDemo.monotonic_time
      end

      def with_deadline_timeout(deadline, message)
        JsonCommandBridgeDemo.with_deadline_timeout(deadline, message) { yield }
      end

      def encode_response(response)
        JsonCommandBridgeDemo.encode_response(response)
      end

      def decode_response(payload)
        JsonCommandBridgeDemo.decode_response(payload)
      end

      def encode_command(command)
        JsonCommandBridgeDemo.encode_command(command)
      end

      def decode_command(payload)
        JsonCommandBridgeDemo.decode_command(payload)
      end

      def response_lines(stdout)
        JsonCommandBridgeDemo.response_lines(stdout)
      end

      def shutdown_response?(response)
        JsonCommandBridgeDemo.shutdown_response?(response)
      end

      def bind_endpoint
        LoopbackSupport.bind_endpoint(ALPN)
      end

      def close_endpoint(endpoint)
        LoopbackSupport.close_endpoint(endpoint)
      end

      def response_for(command, context)
        command = JsonCommandBridgeDemo.stringify_keys(command)
        request_id = command["request_id"]
        op = command["op"].to_s

        case op
        when "echo"
          JsonCommandBridgeDemo.ok_response(request_id, op, "message" => command.dig("params", "message").to_s)
        when "identify"
          JsonCommandBridgeDemo.ok_response(
            request_id,
            op,
            "server_id" => context.fetch(:server_id),
            "remote_id" => context.fetch(:remote_id),
            "alpn" => ALPN,
            "server_app" => context.fetch(:server_app),
            "rails_env" => context.fetch(:rails_env),
            "rails_version" => context.fetch(:rails_version)
          )
        when "stats"
          JsonCommandBridgeDemo.ok_response(
            request_id,
            op,
            "handled_commands" => context.fetch(:handled_commands),
            "connection_stable_id" => context.fetch(:connection_stable_id),
            "paths" => context.fetch(:paths),
            "server_app" => context.fetch(:server_app)
          )
        when "shutdown"
          JsonCommandBridgeDemo.ok_response(request_id, op, "shutdown" => true)
        else
          JsonCommandBridgeDemo.error_response(request_id, op, "unsupported command: #{op}")
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
            rails_env,
            RbConfig.ruby,
            SERVER_BIN_PATH,
            "runner",
            "RailsPairServer::Runner.run"
          )
          server_stdin.close
          server_err_reader = Thread.new { server_stderr.read }
          ticket_line = with_deadline_timeout(deadline, "timed out waiting for Rails pair server") do
            loop do
              line = server_stdout.gets
              raise "Rails pair server exited before printing a ticket" unless line

              line = line.chomp
              break line if line.start_with?("ticket: ")
            end
          end
          ticket = ticket_line.sub(/\Aticket:\s*/, "")
          message = normalize_message(message)

          client_stdout, client_stderr, client_status = with_deadline_timeout(
            deadline,
            "timed out running Rails pair client"
          ) do
            Open3.capture3(
              rails_env(
                "IROH_RAILS_PAIR_TICKET" => ticket,
                "IROH_RAILS_PAIR_MESSAGE" => message
              ),
              RbConfig.ruby,
              CLIENT_BIN_PATH,
              "runner",
              "RailsPairClient::Runner.run"
            )
          end

          server_stdout_tail = with_deadline_timeout(deadline, "timed out waiting for Rails pair server exit") do
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

      def rails_env(overrides = {})
        {
          "RAILS_ENV" => "development",
          "IROH_RAILS_PAIR_TIMEOUT" => DEFAULT_TIMEOUT_SECONDS.to_s
        }.merge(overrides)
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
          :app_name,
          keyword_init: true
        )

        module_function

        def run_once(timeout: RailsPairDemo::DEFAULT_TIMEOUT_SECONDS, out: $stdout,
                     app_name: "server_app", rails_env: "development", rails_version: nil)
          timeout_seconds = RailsPairDemo.normalize_timeout_seconds(timeout)
          deadline = RailsPairDemo.monotonic_time + timeout_seconds
          server = RailsPairDemo.with_deadline_timeout(deadline, "timed out binding Rails pair server endpoint") do
            RailsPairDemo.bind_endpoint
          end
          server_id = server.id.to_s
          ticket = Iroh::EndpointTicket.from_addr(server.addr).to_s
          rails_version ||= defined?(Rails) ? Rails.version : "unknown"

          out.puts "ticket: #{ticket}"
          out.flush if out.respond_to?(:flush)

          incoming = RailsPairDemo.with_deadline_timeout(deadline, "timed out waiting for Rails pair client") do
            server.accept_next
          end
          raise "Rails pair server endpoint closed before accepting a connection" unless incoming

          accepting = RailsPairDemo.with_deadline_timeout(deadline, "timed out accepting Rails pair client") do
            incoming.accept
          end
          connection = RailsPairDemo.with_deadline_timeout(deadline, "timed out establishing Rails pair connection") do
            accepting.connect
          end

          responses = handle_connection(
            server,
            connection,
            deadline,
            app_name: app_name,
            rails_env: rails_env,
            rails_version: rails_version
          )
          RailsPairDemo.with_deadline_timeout(deadline, "timed out waiting for Rails pair client close") do
            connection.closed
          end
          RailsPairDemo.close_endpoint(server)

          Result.new(
            server_id: server_id,
            ticket: ticket,
            alpn: RailsPairDemo::ALPN,
            responses: responses,
            handled_commands: responses.length,
            server_closed: server.is_closed,
            app_name: app_name
          )
        ensure
          RailsPairDemo.close_endpoint(server)
        end

        def handle_connection(server, connection, deadline, app_name:, rails_env:, rails_version:)
          responses = []

          JsonCommandBridgeDemo::MAX_COMMANDS.times do
            stream = RailsPairDemo.with_deadline_timeout(deadline, "timed out accepting Rails pair stream") do
              connection.accept_bi
            end
            payload = RailsPairDemo.with_deadline_timeout(deadline, "timed out reading Rails pair command") do
              stream.recv.read_to_end(JsonCommandBridgeDemo::MAX_PAYLOAD_BYTES)
            end
            response = response_for_payload(
              payload,
              server: server,
              connection: connection,
              handled_commands: responses.length + 1,
              app_name: app_name,
              rails_env: rails_env,
              rails_version: rails_version
            )
            RailsPairDemo.with_deadline_timeout(deadline, "timed out writing Rails pair response") do
              stream.send.write_all(RailsPairDemo.encode_response(response))
            end
            RailsPairDemo.with_deadline_timeout(deadline, "timed out finishing Rails pair response") do
              stream.send.finish
            end

            responses << response
            break if RailsPairDemo.shutdown_response?(response)
          end

          responses
        end

        def response_for_payload(payload, server:, connection:, handled_commands:, app_name:, rails_env:, rails_version:)
          command = RailsPairDemo.decode_command(payload)
          RailsPairDemo.response_for(
            command,
            server_id: server.id.to_s,
            remote_id: connection.remote_id.to_s,
            handled_commands: handled_commands,
            connection_stable_id: connection.stable_id,
            paths: connection.paths.length,
            server_app: app_name,
            rails_env: rails_env,
            rails_version: rails_version
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
          :app_name,
          keyword_init: true
        )

        module_function

        def deliver(ticket, commands = RailsPairDemo.default_commands,
                    timeout: RailsPairDemo::DEFAULT_TIMEOUT_SECONDS, app_name: "client_app")
          timeout_seconds = RailsPairDemo.normalize_timeout_seconds(timeout)
          deadline = RailsPairDemo.monotonic_time + timeout_seconds
          ticket = RailsPairDemo.normalize_ticket(ticket)
          commands = commands.map { |command| JsonCommandBridgeDemo.stringify_keys(command) }
          parsed_addr = RailsPairDemo.with_deadline_timeout(deadline, "timed out parsing Rails pair ticket") do
            Iroh::EndpointTicket.from_string(ticket).endpoint_addr
          end
          sender = RailsPairDemo.with_deadline_timeout(deadline, "timed out binding Rails pair client endpoint") do
            RailsPairDemo.bind_endpoint
          end
          sender_id = sender.id.to_s
          receiver_id = parsed_addr.id.to_s
          connection = RailsPairDemo.with_deadline_timeout(deadline, "timed out connecting Rails pair client") do
            sender.connect(parsed_addr, RailsPairDemo::ALPN)
          end
          responses = commands.map do |command|
            send_command(connection, command, deadline)
          end

          RailsPairDemo.close_endpoint(sender)

          Result.new(
            sender_id: sender_id,
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: RailsPairDemo::ALPN,
            commands: commands,
            responses: responses,
            sender_closed: sender.is_closed,
            app_name: app_name
          )
        ensure
          RailsPairDemo.close_endpoint(sender)
        end

        def send_command(connection, command, deadline)
          stream = RailsPairDemo.with_deadline_timeout(deadline, "timed out opening Rails pair stream") do
            connection.open_bi
          end
          RailsPairDemo.with_deadline_timeout(deadline, "timed out writing Rails pair command") do
            stream.send.write_all(RailsPairDemo.encode_command(command))
          end
          RailsPairDemo.with_deadline_timeout(deadline, "timed out finishing Rails pair command") do
            stream.send.finish
          end
          payload = RailsPairDemo.with_deadline_timeout(deadline, "timed out reading Rails pair response") do
            stream.recv.read_to_end(JsonCommandBridgeDemo::MAX_PAYLOAD_BYTES)
          end

          RailsPairDemo.decode_response(payload)
        end
      end
    end
  end
end
