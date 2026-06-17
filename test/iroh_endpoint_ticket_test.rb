# frozen_string_literal: true

require "test_helper"

class IrohEndpointTicketTest < Minitest::Test
  FIXED_ENDPOINT_ID_BYTES = [
    0x52, 0x3c, 0x79, 0x96, 0xba, 0xd7, 0x74, 0x24,
    0xe9, 0x67, 0x86, 0xcf, 0x7a, 0x72, 0x05, 0x11,
    0x53, 0x37, 0xa5, 0xb4, 0x56, 0x5c, 0xd2, 0x55,
    0x06, 0xa0, 0xf2, 0x97, 0xb1, 0x91, 0xa5, 0xea
  ].pack("C*")

  def test_endpoint_id_round_trip
    endpoint_id = Iroh::EndpointId.from_bytes(FIXED_ENDPOINT_ID_BYTES)

    assert_equal FIXED_ENDPOINT_ID_BYTES, endpoint_id.to_bytes
    assert_equal endpoint_id.to_s, Iroh::EndpointId.from_string(endpoint_id.to_s).to_s
    assert_equal "523c7996ba", endpoint_id.fmt_short
  end

  def test_endpoint_ticket_round_trip
    endpoint_id = Iroh::EndpointId.from_bytes(FIXED_ENDPOINT_ID_BYTES)
    addr = Iroh::EndpointAddr.new(endpoint_id, nil, [])
    ticket = Iroh::EndpointTicket.from_addr(addr)

    assert_equal addr.to_s, ticket.endpoint_addr.to_s
    assert_equal ticket.to_s, Iroh::EndpointTicket.from_string(ticket.to_s).to_s
  end
end
