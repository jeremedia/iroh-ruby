# frozen_string_literal: true

require "fileutils"
require "mkmf"
require "rbconfig"

ROOT = File.expand_path("../..", __dir__)
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

unless system("cargo", "--version", out: File::NULL)
  abort "cargo is required to build the iroh native library"
end

FileUtils.mkdir_p(NATIVE_DIR)
env = { "CARGO_TARGET_DIR" => TARGET_DIR }
ok = system(env, "cargo", "build", "--release", "--lib", chdir: VENDOR_DIR)
abort "cargo build failed for vendored iroh-ffi" unless ok

source = File.join(TARGET_DIR, "release", dynamic_library_filename)
abort "expected native library was not built: #{source}" unless File.file?(source)

FileUtils.cp(source, File.join(NATIVE_DIR, dynamic_library_filename))
create_makefile("iroh_ffi")
