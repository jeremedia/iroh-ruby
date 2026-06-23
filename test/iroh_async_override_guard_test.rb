# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "test_helper"

class IrohAsyncOverrideGuardTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_async_override_registry_has_unique_entries
    keys = overrides.map { |override| override_key(override) }

    assert_equal keys.uniq, keys
    assert_equal 52, overrides.length
  end

  def test_patched_override_methods_exist_with_expected_arity
    overrides.each do |override|
      klass = IrohFfi.const_get(override.target)
      actual_arity = if override.scope == :singleton
                       assert klass.respond_to?(override.method_name, true), "#{override_key(override)} is missing"
                       klass.method(override.method_name).arity
                     else
                       assert method_defined_on?(klass, override.method_name), "#{override_key(override)} is missing"
                       klass.instance_method(override.method_name).arity
                     end

      assert_equal override.arity, actual_arity, "#{override_key(override)} arity drifted"
    end
  end

  def test_generated_methods_and_backing_symbols_still_exist
    generated = generated_override_inventory

    overrides.each do |override|
      row = generated.fetch(override_key(override))

      assert row.fetch("method_exists"), "#{override_key(override)} is missing from generated binding"
      assert_equal override.arity, row.fetch("arity"), "#{override_key(override)} generated arity drifted"
      assert row.fetch("ffi_exists"), "#{override.ffi_function} is missing from UniFFILib"
    end
  end

  private

  def overrides
    IrohFfiAsyncPatches::OVERRIDES
  end

  def override_key(override)
    "#{override.target}.#{override.scope}.#{override.method_name}"
  end

  def method_defined_on?(klass, method_name)
    klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
  end

  def generated_override_inventory
    rows = overrides.map do |override|
      {
        target: override.target,
        method_name: override.method_name,
        scope: override.scope,
        ffi_function: override.ffi_function,
        key: override_key(override)
      }
    end
    script = <<~'RUBY'
      require "json"
      require "iroh/version"
      require "iroh/native"
      require "iroh/generated/iroh_ffi"

      lib = IrohFfi.const_get(:UniFFILib)
      rows = JSON.parse(ENV.fetch("IROH_OVERRIDE_ROWS"))
      result = rows.map do |row|
        klass = IrohFfi.const_get(row.fetch("target"))
        method_name = row.fetch("method_name").to_sym
        if row.fetch("scope") == "singleton"
          method_exists = klass.respond_to?(method_name, true)
          arity = method_exists ? klass.method(method_name).arity : nil
        else
          method_exists = klass.method_defined?(method_name) || klass.private_method_defined?(method_name)
          arity = method_exists ? klass.instance_method(method_name).arity : nil
        end

        {
          key: row.fetch("key"),
          method_exists: method_exists,
          arity: arity,
          ffi_exists: lib.respond_to?(row.fetch("ffi_function").to_sym, true)
        }
      end

      puts JSON.generate(result)
    RUBY
    stdout, stderr, status = Open3.capture3(
      { "IROH_OVERRIDE_ROWS" => JSON.generate(rows) },
      RbConfig.ruby,
      "-Ilib",
      "-e",
      script,
      chdir: ROOT
    )
    assert status.success?, stderr

    JSON.parse(stdout).to_h { |row| [row.fetch("key"), row] }
  end
end
