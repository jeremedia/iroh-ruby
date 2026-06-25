# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"

require "iroh"

module Iroh
  module Examples
    module JsonCommandBridgeDemo
      ALPN = "iroh-ruby/demo/json-command-bridge"
      DEFAULT_MESSAGE = "hello from json bridge"
      DEFAULT_TIMEOUT_SECONDS = Iroh::JsonBridge::DEFAULT_TIMEOUT_SECONDS
      MAX_PAYLOAD_BYTES = Iroh::JsonBridge::MAX_PAYLOAD_BYTES
      MAX_COMMANDS = Iroh::JsonBridge::MAX_COMMANDS
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

      def endpoint_options
        Iroh::EndpointOptions.new(
          preset: Iroh.preset_minimal,
          relay_mode: Iroh::RelayMode.disabled,
          bind_addr: "127.0.0.1:0",
          alpns: [ALPN]
        )
      end

      def router
        Iroh::JsonBridge::CommandRouter.new.tap do |router|
          router.on("echo") do |command, _context|
            { "message" => command.dig("params", "message").to_s }
          end
          router.on("identify") do |_command, context|
            {
              "server_id" => context.fetch(:server_id),
              "remote_id" => context.fetch(:remote_id),
              "alpn" => ALPN
            }
          end
          router.on("stats") do |_command, context|
            {
              "handled_commands" => context.fetch(:handled_commands),
              "connection_stable_id" => context.fetch(:connection_stable_id),
              "paths" => context.fetch(:paths)
            }
          end
          router.on("shutdown") do |_command, _context|
            { "shutdown" => true }
          end
        end
      end

      def normalize_ticket(ticket)
        Iroh::JsonBridge.normalize_ticket(ticket)
      end

      def normalize_message(message)
        Iroh::JsonBridge.normalize_message(message)
      end

      def normalize_payload(payload)
        Iroh::JsonBridge.normalize_payload(payload)
      end

      def with_deadline_timeout(deadline, message)
        timeout_seconds = remaining_timeout(deadline, message)
        Timeout.timeout(timeout_seconds, Timeout::Error,
                        "#{message} after #{format_timeout_seconds(timeout_seconds)} seconds") do
          yield
        end
      end

      def normalize_timeout_seconds(timeout)
        seconds = Float(timeout)
        raise ArgumentError, "timeout must be positive" unless seconds.positive?

        seconds
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def encode_command(command)
        Iroh::JsonBridge.encode_command(command)
      end

      def decode_command(payload)
        Iroh::JsonBridge.decode_command(payload)
      end

      def encode_response(response)
        Iroh::JsonBridge.encode_response(response)
      end

      def decode_response(payload)
        Iroh::JsonBridge.decode_response(payload)
      end

      def response_for(command, context)
        router.call(command, context)
      end

      def ok_response(request_id, op, result)
        Iroh::JsonBridge.ok_response(request_id, op, result)
      end

      def error_response(request_id, op, error)
        Iroh::JsonBridge.error_response(request_id, op, error)
      end

      def shutdown_response?(response)
        Iroh::JsonBridge.shutdown_response?(response)
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

      def remaining_timeout(deadline, message)
        remaining = deadline - monotonic_time
        return remaining if remaining.positive?

        raise Timeout::Error, message
      end

      def format_timeout_seconds(seconds)
        seconds == seconds.to_i ? seconds.to_i.to_s : seconds.to_s
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
        module_function

        def run_once(timeout: JsonCommandBridgeDemo::DEFAULT_TIMEOUT_SECONDS, out: $stdout)
          Iroh::JsonBridge::Server.new(
            endpoint_options: JsonCommandBridgeDemo.endpoint_options,
            alpn: JsonCommandBridgeDemo::ALPN,
            router: JsonCommandBridgeDemo.router,
            timeout: timeout
          ).run_once(out: out)
        end
      end

      module Client
        module_function

        def deliver(ticket, commands = JsonCommandBridgeDemo.default_commands,
                    timeout: JsonCommandBridgeDemo::DEFAULT_TIMEOUT_SECONDS)
          Iroh::JsonBridge::Client.new(
            endpoint_options: JsonCommandBridgeDemo.endpoint_options,
            alpn: JsonCommandBridgeDemo::ALPN,
            timeout: timeout
          ).deliver(ticket, commands)
        end
      end
    end
  end
end
