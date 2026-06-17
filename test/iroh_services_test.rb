# frozen_string_literal: true

require "test_helper"

class IrohServicesTest < Minitest::Test
  def test_submit_network_diagnostics_accepts_send_flag
    assert_equal 1, Iroh::ServicesClient.instance_method(:submit_network_diagnostics).arity
  end
end
