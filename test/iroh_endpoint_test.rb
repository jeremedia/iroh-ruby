# frozen_string_literal: true

require "test_helper"

class IrohEndpointTest < Minitest::Test
  def test_endpoint_binds_with_minimal_offline_preset
    endpoint = Iroh::Endpoint.bind(
      Iroh::EndpointOptions.new(
        preset: Iroh.preset_minimal,
        relay_mode: Iroh::RelayMode.disabled,
        bind_addr: "127.0.0.1:0"
      )
    )

    assert_kind_of Iroh::EndpointId, endpoint.id
    assert_kind_of Iroh::EndpointAddr, endpoint.addr
    refute_empty endpoint.bound_sockets
    refute endpoint.is_closed
  ensure
    endpoint&.close
  end
end
