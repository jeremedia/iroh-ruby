# frozen_string_literal: true

require "open3"
require "rbconfig"

require_relative "loopback_support"

module Iroh
  module Examples
    module ConnectionTelemetryDemo
      ALPN = "iroh-ruby/demo/connection-telemetry"
      DEFAULT_MESSAGE = "hello from telemetry land"
      DEFAULT_TIMEOUT_SECONDS = 10
      MAX_PAYLOAD_BYTES = 1_048_576
      SCRIPT_PATH = File.expand_path("../connection_telemetry.rb", __dir__)

      CONNECTION_STATS_KEYS = %i[
        udp_tx_datagrams
        udp_tx_bytes
        udp_rx_datagrams
        udp_rx_bytes
        lost_packets
        lost_bytes
      ].freeze
      PATH_STATS_KEYS = %i[
        rtt_ms
        udp_tx_datagrams
        udp_tx_bytes
        udp_rx_datagrams
        udp_rx_bytes
        cwnd
        congestion_events
        lost_packets
        lost_bytes
        current_mtu
      ].freeze

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

      def telemetry_snapshot(endpoint:, connection:, remote_id: nil)
        paths = connection.paths.map { |path| path_snapshot_hash(path) }
        {
          endpoint_id: stringify_value(endpoint.id),
          endpoint_online: nil,
          endpoint_remote_addr: remote_id ? stringify_value(endpoint.remote_addr(remote_id)) : nil,
          endpoint_stats: endpoint_stats_hash(endpoint.stats),
          connection: {
            remote_id: stringify_value(connection.remote_id),
            stable_id: connection.stable_id,
            side: side_name(connection.side),
            rtt_ms: connection.rtt,
            stats: connection_stats_hash(connection.stats)
          },
          paths: paths,
          path_summary: path_summary(paths)
        }
      end

      def connection_stats_hash(stats)
        stats_hash(stats, CONNECTION_STATS_KEYS)
      end

      def path_stats_hash(stats)
        return nil unless stats

        stats_hash(stats, PATH_STATS_KEYS)
      end

      def path_snapshot_hash(path)
        {
          id: path.id,
          is_selected: !!path.is_selected,
          remote_addr: stringify_value(path.remote_addr),
          is_ip: !!path.is_ip,
          is_relay: !!path.is_relay,
          rtt_ms: path.rtt_ms,
          stats: path_stats_hash(path.stats)
        }
      end

      def endpoint_stats_hash(stats)
        return {} unless stats

        stats.keys.map(&:to_s).sort.each_with_object({}) do |key, memo|
          stat = stats[key]
          memo[key] = {
            value: stat.value,
            description: stat.description.to_s
          }
        end
      end

      def path_summary(paths)
        {
          total: paths.length,
          selected: paths.count { |path| path[:is_selected] },
          relay: paths.count { |path| path[:is_relay] },
          rtt_observed: paths.any? { |path| !path[:rtt_ms].nil? }
        }
      end

      def format_telemetry(label, snapshot)
        connection = snapshot.fetch(:connection)
        summary = snapshot.fetch(:path_summary)
        stats = connection.fetch(:stats)
        [
          "#{label} endpoint: id=#{snapshot[:endpoint_id]} online=#{format_optional(snapshot[:endpoint_online])} " \
          "remote_addr=#{format_optional(snapshot[:endpoint_remote_addr])}",
          "#{label} connection: remote=#{connection[:remote_id]} stable_id=#{connection[:stable_id]} " \
          "side=#{connection[:side]} rtt_ms=#{format_optional(connection[:rtt_ms])}",
          "#{label} paths: total=#{summary[:total]} selected=#{summary[:selected]} relay=#{summary[:relay]} " \
          "rtt_observed=#{summary[:rtt_observed]}",
          "#{label} connection stats: tx=#{stats[:udp_tx_datagrams]}/#{stats[:udp_tx_bytes]}B " \
          "rx=#{stats[:udp_rx_datagrams]}/#{stats[:udp_rx_bytes]}B " \
          "lost=#{stats[:lost_packets]}/#{stats[:lost_bytes]}B"
        ] + format_paths(label, snapshot.fetch(:paths))
      end

      def format_paths(label, paths)
        paths.map do |path|
          "#{label} path #{path[:id]}: selected=#{path[:is_selected]} relay=#{path[:is_relay]} " \
            "ip=#{path[:is_ip]} rtt_ms=#{format_optional(path[:rtt_ms])} remote=#{path[:remote_addr]}"
        end
      end

      def format_optional(value)
        value.nil? ? "unknown" : value.to_s
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
            SCRIPT_PATH,
            "server"
          )
          server_stdin.close
          server_err_reader = Thread.new { server_stderr.read }
          ticket_line = with_deadline_timeout(deadline, "timed out waiting for connection telemetry server") do
            loop do
              line = server_stdout.gets
              raise "connection telemetry server exited before printing a ticket" unless line

              line = line.chomp
              break line if line.start_with?("ticket: ")
            end
          end
          ticket = ticket_line.sub(/\Aticket:\s*/, "")
          message = normalize_message(message)

          client_stdout, client_stderr, client_status = with_deadline_timeout(
            deadline,
            "timed out running connection telemetry client"
          ) do
            Open3.capture3(
              RbConfig.ruby,
              SCRIPT_PATH,
              "client",
              ticket,
              message
            )
          end

          server_stdout_tail = with_deadline_timeout(
            deadline,
            "timed out waiting for connection telemetry server exit"
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
            server_stdout: server_stdout_tail
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

      def stats_hash(stats, keys)
        keys.each_with_object({}) do |key, memo|
          memo[key] = stats.public_send(key)
        end
      end

      def side_name(side)
        return "CLIENT" if defined?(Iroh::Side::CLIENT) && side == Iroh::Side::CLIENT
        return "SERVER" if defined?(Iroh::Side::SERVER) && side == Iroh::Side::SERVER

        side.to_s
      end

      def stringify_value(value)
        value.nil? ? nil : value.to_s
      end

      ProcessResult = Struct.new(
        :ticket,
        :message,
        :client_stdout,
        :server_stdout,
        keyword_init: true
      )

      module Server
        Result = Struct.new(
          :receiver_id,
          :ticket,
          :alpn,
          :received,
          :sent,
          :telemetry,
          :receiver_closed,
          keyword_init: true
        )

        module_function

        def run_once(timeout: ConnectionTelemetryDemo::DEFAULT_TIMEOUT_SECONDS, out: $stdout)
          timeout_seconds = ConnectionTelemetryDemo.normalize_timeout_seconds(timeout)
          deadline = ConnectionTelemetryDemo.monotonic_time + timeout_seconds
          receiver = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out binding telemetry server endpoint") do
            ConnectionTelemetryDemo.bind_endpoint
          end
          receiver_id = receiver.id.to_s
          ticket = Iroh::EndpointTicket.from_addr(receiver.addr).to_s

          out.puts "ticket: #{ticket}"
          out.flush if out.respond_to?(:flush)

          incoming = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out waiting for telemetry client") do
            receiver.accept_next
          end
          raise "server endpoint closed before accepting a connection" unless incoming

          accepting = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out accepting telemetry client") do
            incoming.accept
          end
          receiver_connection = ConnectionTelemetryDemo.with_deadline_timeout(
            deadline,
            "timed out establishing telemetry server connection"
          ) do
            accepting.connect
          end
          receiver_stream = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out accepting telemetry stream") do
            receiver_connection.accept_bi
          end
          received = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out reading telemetry request") do
            ConnectionTelemetryDemo.normalize_payload(
              receiver_stream.recv.read_to_end(ConnectionTelemetryDemo::MAX_PAYLOAD_BYTES)
            )
          end
          response = ConnectionTelemetryDemo.normalize_message("telemetry echo: #{received}")

          ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out writing telemetry response") do
            receiver_stream.send.write_all(response)
          end
          ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out finishing telemetry response") do
            receiver_stream.send.finish
          end
          telemetry = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out capturing server telemetry") do
            ConnectionTelemetryDemo.telemetry_snapshot(
              endpoint: receiver,
              connection: receiver_connection,
              remote_id: receiver_connection.remote_id
            )
          end
          ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out waiting for telemetry client close") do
            receiver_connection.closed
          end

          ConnectionTelemetryDemo.close_endpoint(receiver)

          Result.new(
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: ConnectionTelemetryDemo::ALPN,
            received: received,
            sent: response,
            telemetry: telemetry,
            receiver_closed: receiver.is_closed
          )
        ensure
          ConnectionTelemetryDemo.close_endpoint(receiver)
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
          :telemetry,
          :sender_closed,
          keyword_init: true
        )

        module_function

        def deliver(ticket, message = ConnectionTelemetryDemo::DEFAULT_MESSAGE,
                    timeout: ConnectionTelemetryDemo::DEFAULT_TIMEOUT_SECONDS)
          timeout_seconds = ConnectionTelemetryDemo.normalize_timeout_seconds(timeout)
          deadline = ConnectionTelemetryDemo.monotonic_time + timeout_seconds
          ticket = ConnectionTelemetryDemo.normalize_ticket(ticket)
          message = ConnectionTelemetryDemo.normalize_message(message)
          parsed_addr = ConnectionTelemetryDemo.with_deadline_timeout(
            deadline,
            "timed out parsing telemetry endpoint ticket"
          ) do
            Iroh::EndpointTicket.from_string(ticket).endpoint_addr
          end
          sender = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out binding telemetry client endpoint") do
            ConnectionTelemetryDemo.bind_endpoint
          end
          sender_id = sender.id.to_s
          receiver_id = parsed_addr.id.to_s

          sender_connection = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out connecting telemetry client") do
            sender.connect(parsed_addr, ConnectionTelemetryDemo::ALPN)
          end
          sender_stream = ConnectionTelemetryDemo.with_deadline_timeout(
            deadline,
            "timed out opening telemetry bidirectional stream"
          ) do
            sender_connection.open_bi
          end

          ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out writing telemetry request") do
            sender_stream.send.write_all(message)
          end
          ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out finishing telemetry request") do
            sender_stream.send.finish
          end

          received = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out reading telemetry response") do
            ConnectionTelemetryDemo.normalize_payload(
              sender_stream.recv.read_to_end(ConnectionTelemetryDemo::MAX_PAYLOAD_BYTES)
            )
          end
          telemetry = ConnectionTelemetryDemo.with_deadline_timeout(deadline, "timed out capturing client telemetry") do
            ConnectionTelemetryDemo.telemetry_snapshot(
              endpoint: sender,
              connection: sender_connection,
              remote_id: parsed_addr.id
            )
          end

          ConnectionTelemetryDemo.close_endpoint(sender)

          Result.new(
            sender_id: sender_id,
            receiver_id: receiver_id,
            ticket: ticket,
            alpn: ConnectionTelemetryDemo::ALPN,
            sent: message,
            received: received,
            telemetry: telemetry,
            sender_closed: sender.is_closed
          )
        ensure
          ConnectionTelemetryDemo.close_endpoint(sender)
        end
      end
    end
  end
end
