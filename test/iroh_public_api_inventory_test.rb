# frozen_string_literal: true

require "test_helper"
require_relative "../tasks/public_api_inventory"

class IrohPublicApiInventoryTest < Minitest::Test
  FIXTURE_PATH = File.expand_path("fixtures/public_api_inventory.txt", __dir__)

  def test_public_api_inventory_matches_fixture
    expected = File.read(FIXTURE_PATH)
    actual = Iroh::Tasks::PublicApiInventory.snapshot

    assert_equal expected, actual, "public API changed; run bundle exec rake api:inventory:update if intentional"
  end
end
