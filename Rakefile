# frozen_string_literal: true

require "rake/testtask"
require "fileutils"
require "rbconfig"

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
end

task test: "native:build"
task default: :test
