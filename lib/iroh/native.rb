# frozen_string_literal: true

require "rbconfig"

module Iroh
  module Native
    module_function

    def library_path
      override = ENV["IROH_FFI_LIBRARY"]
      return override unless override.nil? || override.empty?

      bundled_library = File.expand_path("native/#{library_filename}", __dir__)
      return bundled_library if File.file?(bundled_library)

      "iroh_ffi"
    end

    def library_filename
      case RbConfig::CONFIG.fetch("host_os")
      when /darwin/
        "libiroh_ffi.dylib"
      when /mswin|mingw/
        "iroh_ffi.dll"
      else
        "libiroh_ffi.so"
      end
    end
  end
end
