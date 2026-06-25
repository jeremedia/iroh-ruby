# frozen_string_literal: true

require "test_helper"
require "rbconfig"
require "stringio"
require "tmpdir"
require_relative "../tasks/installed_gem_smoke"

class IrohInstalledGemSmokeTest < Minitest::Test
  def test_builds_gem_install_command_without_local_only_mode
    command = Iroh::Tasks::InstalledGemSmoke.install_command(
      gem_file: "/tmp/iroh-0.1.0.gem",
      gem_home: "/tmp/gems",
      bindir: "/tmp/gems/bin"
    )

    assert_equal "gem", command.first
    assert_includes command, "install"
    assert_includes command, "/tmp/iroh-0.1.0.gem"
    assert_includes command, "--install-dir"
    assert_includes command, "/tmp/gems"
    assert_includes command, "--bindir"
    assert_includes command, "/tmp/gems/bin"
    assert_includes command, "--no-document"
    refute_includes command, "--local"
  end

  def test_smoke_environment_uses_isolated_gem_paths_and_unsets_repo_loaders
    env = Iroh::Tasks::InstalledGemSmoke.smoke_env("/tmp/gems")

    assert_equal "/tmp/gems", env.fetch("GEM_HOME")
    assert_equal "/tmp/gems", env.fetch("GEM_PATH")
    assert_nil env.fetch("BUNDLE_GEMFILE")
    assert_nil env.fetch("BUNDLE_BIN_PATH")
    assert_nil env.fetch("RUBYLIB")
    assert_nil env.fetch("RUBYOPT")
  end

  def test_smoke_script_requires_installed_gem_without_repo_load_path
    script = Iroh::Tasks::InstalledGemSmoke.smoke_script

    assert_includes script, 'require "iroh"'
    assert_includes script, "Iroh::SecretKey.generate"
    assert_includes script, "Iroh::Endpoint.bind"
    assert_includes script, "Iroh::EndpointTicket.from_addr"
    assert_includes script, "Iroh::JsonBridge.encode_command"
    assert_includes script, "Iroh::JsonBridge.decode_command"
    refute_includes script, "$LOAD_PATH.unshift"
    refute_includes script, "-Ilib"
  end

  def test_smoke_script_is_valid_ruby
    RubyVM::InstructionSequence.compile(Iroh::Tasks::InstalledGemSmoke.smoke_script)
  end

  def test_gem_file_uses_project_version
    assert_equal File.join(Dir.pwd, "iroh-#{Iroh::VERSION}.gem"),
                 Iroh::Tasks::InstalledGemSmoke.gem_file(Dir.pwd)
  end

  def test_run_command_uses_unbundled_subprocess_environment
    Dir.mktmpdir("iroh-smoke-env-test-") do |gem_home|
      out = StringIO.new
      script = <<~RUBY
        raise "bundler leaked through RUBYOPT" if ENV["RUBYOPT"].to_s.include?("bundler/setup")
        raise "bundler leaked through BUNDLE_GEMFILE" if ENV["BUNDLE_GEMFILE"].to_s.end_with?("Gemfile")
        raise "wrong GEM_HOME" unless ENV["GEM_HOME"] == #{gem_home.inspect}
        puts "subprocess env ok"
      RUBY

      Iroh::Tasks::InstalledGemSmoke.run_command(
        Iroh::Tasks::InstalledGemSmoke.smoke_env(gem_home),
        [RbConfig.ruby, "-e", script],
        chdir: gem_home,
        label: "ruby env test",
        out: out
      )
      Iroh::Tasks::InstalledGemSmoke.run_command(
        Iroh::Tasks::InstalledGemSmoke.smoke_env(gem_home),
        ["gem", "env", "home"],
        chdir: gem_home,
        label: "gem env test",
        out: out
      )

      assert_includes out.string, "subprocess env ok"
      assert_includes out.string, gem_home
    end
  end
end
