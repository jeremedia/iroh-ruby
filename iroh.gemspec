# frozen_string_literal: true

require_relative "lib/iroh/version"

Gem::Specification.new do |spec|
  spec.name = "iroh"
  spec.version = Iroh::VERSION
  spec.authors = ["Jeremy Roush"]
  spec.email = ["jeremedia@users.noreply.github.com"]

  spec.summary = "Ruby bindings for the Iroh networking project."
  spec.description = "A Ruby gem wrapping the Iroh 1.0 FFI surface with generated UniFFI bindings and Ruby ergonomics."
  spec.homepage = "https://www.iroh.computer/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jeremedia/iroh-ruby"
  spec.metadata["documentation_uri"] = "https://docs.iroh.computer/"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*.rb",
      "ext/**/*",
      "vendor/iroh-ffi/{Cargo.toml,Cargo.lock,build.rs,iroh.pc.in,uniffi.toml,uniffi-bindgen.rs,LICENSE-*}",
      "vendor/iroh-ffi/src/**/*.rs",
      "README.md",
      "LICENSE.txt",
      "CHANGELOG.md"
    ]
  end
  spec.bindir = "exe"
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/iroh_ffi/extconf.rb"]

  spec.add_dependency "ffi", "~> 1.17"

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.2"
end
