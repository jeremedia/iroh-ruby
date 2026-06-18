# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../lib/iroh/version"

module Iroh
  module Tasks
    module InstalledGemSmoke
      SMOKE_ALPN = "iroh-ruby/smoke/installed-gem"

      module_function

      def run(root:, out: $stdout)
        built_gem = build_gem(root: root, out: out)

        Dir.mktmpdir("iroh-installed-gem-smoke-") do |tmpdir|
          gem_home = File.join(tmpdir, "gems")
          bindir = File.join(gem_home, "bin")
          consumer_dir = File.join(tmpdir, "consumer")
          script_path = File.join(consumer_dir, "installed_gem_smoke.rb")

          FileUtils.mkdir_p([bindir, consumer_dir])
          run_command(
            smoke_env(gem_home),
            install_command(gem_file: built_gem, gem_home: gem_home, bindir: bindir),
            chdir: root,
            label: "installed-gem smoke install",
            out: out
          )

          File.write(script_path, smoke_script)
          run_command(
            smoke_env(gem_home),
            [RbConfig.ruby, script_path],
            chdir: consumer_dir,
            label: "installed-gem smoke runtime",
            out: out
          )
        end
      end

      def build_gem(root:, out: $stdout)
        run_command(
          {},
          ["gem", "build", "iroh.gemspec"],
          chdir: root,
          label: "gem build",
          out: out
        )
        gem_file(root)
      end

      def gem_file(root)
        File.join(root, "iroh-#{Iroh::VERSION}.gem")
      end

      def install_command(gem_file:, gem_home:, bindir:)
        [
          "gem",
          "install",
          gem_file,
          "--install-dir",
          gem_home,
          "--bindir",
          bindir,
          "--no-document"
        ]
      end

      def smoke_env(gem_home)
        {
          "GEM_HOME" => gem_home,
          "GEM_PATH" => gem_home,
          "BUNDLE_GEMFILE" => nil,
          "BUNDLE_BIN_PATH" => nil,
          "RUBYLIB" => nil,
          "RUBYOPT" => nil
        }
      end

      def smoke_script
        <<~RUBY
          # frozen_string_literal: true

          endpoint = nil

          begin
            require "iroh"

            raise "empty Iroh::VERSION" if Iroh::VERSION.to_s.empty?

            library_path = Iroh::Native.library_path
            raise "native library missing: \#{library_path}" unless File.file?(library_path)

            secret = Iroh::SecretKey.generate
            payload = "installed gem smoke"
            signature = secret.sign(payload)
            secret.public.verify(payload, signature)

            endpoint = Iroh::Endpoint.bind(
              Iroh::EndpointOptions.new(
                preset: Iroh.preset_minimal,
                relay_mode: Iroh::RelayMode.disabled,
                bind_addr: "127.0.0.1:0",
                alpns: [#{SMOKE_ALPN.inspect}]
              )
            )

            ticket = Iroh::EndpointTicket.from_addr(endpoint.addr).to_s
            raise "empty endpoint ticket" if ticket.empty?

            endpoint.close
            raise "endpoint did not close" unless endpoint.is_closed

            puts "installed gem smoke ok: iroh \#{Iroh::VERSION} ticket_bytes=\#{ticket.bytesize}"
          ensure
            endpoint&.close unless endpoint&.is_closed
          end
      RUBY
      end

      def run_command(env, command, chdir:, label:, out:)
        out.puts "$ #{command.join(' ')}"
        stdout, stderr, status = capture_command(env, command, chdir: chdir)
        out.print stdout unless stdout.empty?
        return if status.success?

        out.print stderr unless stderr.empty?
        raise "#{label} failed with status #{status.exitstatus}"
      end

      def capture_command(env, command, chdir:)
        if defined?(Bundler)
          Bundler.with_unbundled_env do
            Open3.capture3(env, *command, chdir: chdir)
          end
        else
          Open3.capture3(env, *command, chdir: chdir)
        end
      end
    end
  end
end
