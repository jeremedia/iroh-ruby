# frozen_string_literal: true

require "test_helper"

class IrohRelayTest < Minitest::Test
  def test_relay_map_from_urls_exposes_membership
    relay_map = Iroh::RelayMap.from_urls(["https://relay.example.test"])

    assert_equal 1, relay_map.len
    refute relay_map.is_empty
    assert relay_map.contains("https://relay.example.test/")
    assert_equal ["https://relay.example.test/"], relay_map.urls
  end

  def test_custom_relay_mode_round_trips_to_map
    relay_mode = Iroh::RelayMode.custom_from_urls(["https://relay.example.test"])
    relay_map = relay_mode.relay_map

    assert relay_map.contains("https://relay.example.test/")
  end
end
