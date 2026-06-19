# frozen_string_literal: true

require "rake/testtask"
require "fileutils"
require "open3"
require "rbconfig"
require "timeout"
require_relative "tasks/installed_gem_smoke"

ROOT = __dir__
VENDOR_DIR = File.join(ROOT, "vendor", "iroh-ffi")
NATIVE_DIR = File.join(ROOT, "lib", "iroh", "native")
TARGET_DIR = File.join(ROOT, "tmp", "cargo-target")

def dynamic_library_filename
  case RbConfig::CONFIG.fetch("host_os")
  when /darwin/
    "libiroh_ffi.dylib"
  when /mswin|mingw/
    "iroh_ffi.dll"
  else
    "libiroh_ffi.so"
  end
end

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.test_files = FileList["test/**/*_test.rb"]
  task.warning = true
end

namespace :native do
  desc "Build the vendored iroh-ffi cdylib into lib/iroh/native"
  task :build do
    FileUtils.mkdir_p(NATIVE_DIR)
    env = { "CARGO_TARGET_DIR" => TARGET_DIR }
    sh env, "cargo", "build", "--release", "--lib", chdir: VENDOR_DIR
    source = File.join(TARGET_DIR, "release", dynamic_library_filename)
    abort "expected native library missing: #{source}" unless File.file?(source)
    FileUtils.cp(source, File.join(NATIVE_DIR, dynamic_library_filename))
  end

  desc "Regenerate the Ruby UniFFI binding from the vendored iroh-ffi crate"
  task generate: :build do
    out_dir = File.join(ROOT, "tmp", "generated")
    FileUtils.rm_rf(out_dir)
    FileUtils.mkdir_p(out_dir)

    library = File.join(TARGET_DIR, "release", dynamic_library_filename)
    sh({ "CARGO_TARGET_DIR" => TARGET_DIR },
       "cargo", "run", "--bin", "uniffi-bindgen", "--",
       "generate",
       "--language", "ruby",
       "--out-dir", out_dir,
       "--config", "uniffi.toml",
       "--library",
       library,
       chdir: VENDOR_DIR)

    generated = File.join(out_dir, "iroh_ffi.rb")
    target = File.join(ROOT, "lib", "iroh", "generated", "iroh_ffi.rb")
    body = File.read(generated)
    body = body.sub("ffi_lib 'iroh_ffi'", "ffi_lib Iroh::Native.library_path")
    File.write(target, body)
  end
end

namespace :demo do
  desc "Run the loopback postcard demo"
  task postcard: "native:build" do
    ruby "examples/postcard.rb", "hello from ruby iroh"
  end

  desc "Run the ticket echo demo"
  task ticket_echo: "native:build" do
    ruby "examples/ticket_echo.rb", "hello from ticket land"
  end

  desc "Run the datagram ping demo"
  task datagram_ping: "native:build" do
    ruby "examples/datagram_ping.rb", "hello from datagram land"
  end

  desc "Run the two-process ticket exchange server"
  task ticket_server: "native:build" do
    ruby "examples/ticket_server.rb"
  end

  desc "Run the two-process ticket exchange client"
  task :ticket_client, [:ticket, :message] => "native:build" do |_task, args|
    abort "usage: bundle exec rake 'demo:ticket_client[ticket,message]'" unless args[:ticket]

    ruby "examples/ticket_client.rb", args[:ticket], args[:message] || "hello from another ruby process"
  end

  desc "Run the automated two-process ticket exchange demo"
  task ticket_exchange: "native:build" do
    server_stdin = nil
    server_stdout = nil
    server_stderr = nil
    server_wait = nil
    server_err_reader = nil

    begin
      server_stdin, server_stdout, server_stderr, server_wait = Open3.popen3(
        RbConfig.ruby,
        "examples/ticket_server.rb"
      )
      server_stdin.close
      server_err_reader = Thread.new { server_stderr.read }
      ticket_line = Timeout.timeout(10, Timeout::Error, "timed out waiting for ticket server") do
        loop do
          line = server_stdout.gets
          abort "ticket server exited before printing a ticket" unless line
          line = line.chomp
          break line if line.start_with?("ticket: ")
        end
      end
      ticket = ticket_line.sub(/\Aticket:\s*/, "")
      message = "hello from another ruby process"

      client_stdout, client_stderr, client_status = Timeout.timeout(
        10,
        Timeout::Error,
        "timed out running ticket exchange client"
      ) do
        Open3.capture3(
          RbConfig.ruby,
          "examples/ticket_client.rb",
          ticket,
          message
        )
      end

      server_stdout_tail = Timeout.timeout(
        10,
        Timeout::Error,
        "timed out waiting for ticket exchange server exit"
      ) do
        server_stdout.read
      end
      server_status = server_wait.value
      server_stderr_text = server_err_reader.value

      abort client_stderr unless client_status.success?
      abort server_stderr_text unless server_status.success?

      puts "iroh-ruby ticket exchange demo"
      puts "ticket:   #{ticket}"
      puts client_stdout
      puts server_stdout_tail
    ensure
      [server_stdout, server_stderr].each do |io|
        io&.close unless io&.closed?
      rescue IOError
        nil
      end
      if server_wait && server_wait.alive?
        Process.kill("TERM", server_wait.pid)
        server_wait.value
      end
    end
  end

  desc "Run the automated connection telemetry demo"
  task connection_telemetry: "native:build" do
    ruby "examples/connection_telemetry.rb"
  end

  desc "Run the protocol router demo"
  task protocol_router: "native:build" do
    ruby "examples/protocol_router.rb"
  end

  desc "Run the endpoint watchers demo"
  task endpoint_watchers: "native:build" do
    ruby "examples/endpoint_watchers.rb"
  end
end

namespace :smoke do
  desc "Build, install, and require the gem from an isolated consumer GEM_HOME"
  task :installed_gem do
    Iroh::Tasks::InstalledGemSmoke.run(root: ROOT)
  end
end

task test: "native:build"
task default: :test
