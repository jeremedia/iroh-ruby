# frozen_string_literal: true

require "test_helper"
require "timeout"
require_relative "../examples/support/postcard_demo"

class IrohPostcardDemoTest < Minitest::Test
  DEMO_TEST_TIMEOUT_SECONDS = Iroh::Examples::PostcardDemo::DEFAULT_TIMEOUT_SECONDS + 5

  def test_delivers_text_payload_between_loopback_endpoints
    message = "hello from ruby iroh"

    result = Timeout.timeout(DEMO_TEST_TIMEOUT_SECONDS) do
      Iroh::Examples::PostcardDemo.deliver(message)
    end

    assert_equal message, result.payload
    assert_equal "iroh-ruby/demo/postcard", result.alpn
    refute_empty result.sender_id
    refute_empty result.receiver_id
    assert result.sender_closed
    assert result.receiver_closed
  end

  def test_times_out_and_closes_endpoints_when_receiver_never_reports
    receiver = FakeEndpoint.new("receiver")
    sender = FakeEndpoint.new("sender", connection: FakeConnection.new)
    endpoints = [receiver, sender]

    error = assert_raises(Timeout::Error) do
      Iroh::Examples::PostcardDemo.stub(:bind_endpoint, -> { endpoints.shift }) do
        Iroh::Examples::PostcardDemo.stub(:receive_one_message, ->(_endpoint, _queue) { sleep }) do
          Iroh::Examples::PostcardDemo.deliver("payload", timeout: 0.05)
        end
      end
    end

    assert_match(/timed out waiting for postcard receiver/, error.message)
    assert receiver.closed?
    assert sender.closed?
  end

  def test_receiver_wait_uses_receiver_timeout_message_after_deadline
    deadline = Iroh::Examples::PostcardDemo.monotonic_time - 0.001

    error = assert_raises(Timeout::Error) do
      Timeout.timeout(0.05) do
        Iroh::Examples::PostcardDemo.wait_for_receiver_result(Queue.new, deadline)
      end
    end

    assert_match(/timed out waiting for postcard receiver/, error.message)
  end

  def test_receiver_thread_wait_returns_for_finished_thread_after_deadline
    receiver_thread = Thread.new { :done }
    receiver_thread.join
    deadline = Iroh::Examples::PostcardDemo.monotonic_time - 0.001

    Iroh::Examples::PostcardDemo.wait_for_receiver_thread(receiver_thread, deadline)
  end

  def test_receiver_thread_wait_raises_receiver_thread_timeout_for_live_thread_after_deadline
    receiver_thread = Thread.new { sleep }
    deadline = Iroh::Examples::PostcardDemo.monotonic_time - 0.001

    error = assert_raises(Timeout::Error) do
      Iroh::Examples::PostcardDemo.wait_for_receiver_thread(receiver_thread, deadline)
    end

    assert_match(/timed out waiting for postcard receiver thread/, error.message)
  ensure
    receiver_thread&.kill
    receiver_thread&.join
  end

  def test_closes_endpoints_when_receiver_reports_error
    receiver = FakeEndpoint.new("receiver")
    sender = FakeEndpoint.new("sender", connection: FakeConnection.new)
    endpoints = [receiver, sender]
    receiver_error = RuntimeError.new("receiver failed")

    error = assert_raises(RuntimeError) do
      Iroh::Examples::PostcardDemo.stub(:bind_endpoint, -> { endpoints.shift }) do
        Iroh::Examples::PostcardDemo.stub(:receive_one_message, ->(_endpoint, queue) { queue << [:error, receiver_error] }) do
          Iroh::Examples::PostcardDemo.deliver("payload", timeout: 1)
        end
      end
    end

    assert_same receiver_error, error
    assert receiver.closed?
    assert sender.closed?
  end

  class FakeEndpoint
    attr_reader :id, :addr

    def initialize(name, connection: nil)
      @id = name
      @addr = "#{name}-addr"
      @connection = connection
      @closed = false
    end

    def connect(_addr, _alpn)
      @connection
    end

    def close
      @closed = true
    end

    def is_closed
      @closed
    end

    def closed?
      @closed
    end
  end

  class FakeConnection
    def open_uni
      FakeSendStream.new
    end
  end

  class FakeSendStream
    def write_all(_message); end

    def finish; end
  end
end
