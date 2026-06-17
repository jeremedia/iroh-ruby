# frozen_string_literal: true

require "test_helper"

class IrohKeyTest < Minitest::Test
  def test_secret_key_sign_verify_round_trip
    secret = Iroh::SecretKey.generate
    message = "hello iroh"

    signature = secret.sign(message)
    public_key = secret.public

    assert_equal 32, secret.to_bytes.bytesize
    assert_equal 64, signature.to_bytes.bytesize
    public_key.verify(message, signature)
  end

  def test_secret_key_can_be_rebuilt_from_raw_bytes
    secret = Iroh::SecretKey.generate
    rebuilt = Iroh::SecretKey.from_bytes(secret.to_bytes)

    assert_equal secret.to_bytes, rebuilt.to_bytes
    assert_equal secret.public.to_s, rebuilt.public.to_s
  end
end
