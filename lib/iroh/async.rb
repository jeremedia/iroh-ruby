# frozen_string_literal: true

require "thread"

module IrohFfi
  module UniFFILib
    callback :iroh_rust_future_continuation_callback, %i[uint64 int8], :void

    attach_function :ffi_iroh_ffi_rust_future_poll_u64,
                    %i[uint64 iroh_rust_future_continuation_callback uint64],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_complete_u64,
                    [:uint64, RustCallStatus.by_ref],
                    :uint64
    attach_function :ffi_iroh_ffi_rust_future_free_u64,
                    [:uint64],
                    :void

    attach_function :ffi_iroh_ffi_rust_future_poll_void,
                    %i[uint64 iroh_rust_future_continuation_callback uint64],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_complete_void,
                    [:uint64, RustCallStatus.by_ref],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_free_void,
                    [:uint64],
                    :void

    attach_function :ffi_iroh_ffi_rust_future_poll_rust_buffer,
                    %i[uint64 iroh_rust_future_continuation_callback uint64],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_complete_rust_buffer,
                    [:uint64, RustCallStatus.by_ref],
                    RustBuffer.by_value
    attach_function :ffi_iroh_ffi_rust_future_free_rust_buffer,
                    [:uint64],
                    :void

    attach_function :ffi_iroh_ffi_rust_future_poll_i8,
                    %i[uint64 iroh_rust_future_continuation_callback uint64],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_complete_i8,
                    [:uint64, RustCallStatus.by_ref],
                    :int8
    attach_function :ffi_iroh_ffi_rust_future_free_i8,
                    [:uint64],
                    :void

    attach_function :ffi_iroh_ffi_rust_future_poll_i32,
                    %i[uint64 iroh_rust_future_continuation_callback uint64],
                    :void
    attach_function :ffi_iroh_ffi_rust_future_complete_i32,
                    [:uint64, RustCallStatus.by_ref],
                    :int32
    attach_function :ffi_iroh_ffi_rust_future_free_i32,
                    [:uint64],
                    :void
  end
end

module Iroh
  module Async
    READY = 0
    UNIFFI_LIB = IrohFfi.const_get(:UniFFILib)

    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @next_token = 0
    @poll_results = {}

    module_function

    def await_u64(future, error: Iroh::Error)
      await_future(future, type: :u64, error: error)
    end

    def await_void(future, error: Iroh::Error)
      await_future(future, type: :void, error: error)
    end

    def await_rust_buffer(future, error: Iroh::Error)
      await_future(future, type: :rust_buffer, error: error)
    end

    def await_i8(future, error: Iroh::Error)
      await_future(future, type: :i8, error: error)
    end

    def await_i32(future, error: Iroh::Error)
      await_future(future, type: :i32, error: error)
    end

    def await_future(future, type:, error:)
      loop do
        token = next_token
        poll(type, future, token)
        poll_code = wait_for_poll(token)
        break if poll_code == READY
      end

      complete(type, future, error)
    ensure
      free(type, future) if future
    end

    def continuation_callback
      @continuation_callback ||= FFI::Function.new(:void, %i[uint64 int8]) do |token, poll_code|
        @mutex.synchronize do
          @poll_results[token] = poll_code
          @condition.broadcast
        end
      end
    end

    def next_token
      @mutex.synchronize do
        @next_token += 1
      end
    end

    def wait_for_poll(token)
      @mutex.synchronize do
        @condition.wait(@mutex) until @poll_results.key?(token)
        @poll_results.delete(token)
      end
    end

    def poll(type, future, token)
      UNIFFI_LIB.public_send(:"ffi_iroh_ffi_rust_future_poll_#{type}", future, continuation_callback, token)
    end

    def complete(type, future, error)
      function = :"ffi_iroh_ffi_rust_future_complete_#{type}"
      if error
        IrohFfi.rust_call_with_error(error, function, future)
      else
        IrohFfi.rust_call(function, future)
      end
    end

    def free(type, future)
      UNIFFI_LIB.public_send(:"ffi_iroh_ffi_rust_future_free_#{type}", future)
    end
  end
end

module IrohFfiAsyncPatches
  RustBuffer = IrohFfi::RustBuffer
  Override = Struct.new(:target, :method_name, :scope, :arity, :ffi_function, keyword_init: true)

  def self.override(target, method_name, scope, arity, ffi_function)
    Override.new(
      target: target,
      method_name: method_name,
      scope: scope,
      arity: arity,
      ffi_function: ffi_function
    )
  end

  OVERRIDES = [
    override("Accepting", :alpn, :instance, 0, :uniffi_iroh_ffi_fn_method_accepting_alpn),
    override("Accepting", :connect, :instance, 0, :uniffi_iroh_ffi_fn_method_accepting_connect),

    override("Connecting", :alpn, :instance, 0, :uniffi_iroh_ffi_fn_method_connecting_alpn),
    override("Connecting", :connect, :instance, 0, :uniffi_iroh_ffi_fn_method_connecting_connect),
    override("Connecting", :remote_id, :instance, 0, :uniffi_iroh_ffi_fn_method_connecting_remote_id),

    override("Incoming", :accept, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_accept),
    override("Incoming", :ignore, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_ignore),
    override("Incoming", :local_addr, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_local_addr),
    override("Incoming", :refuse, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_refuse),
    override("Incoming", :remote_addr, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_remote_addr),
    override("Incoming", :remote_addr_validated, :instance, 0,
             :uniffi_iroh_ffi_fn_method_incoming_remote_addr_validated),
    override("Incoming", :retry, :instance, 0, :uniffi_iroh_ffi_fn_method_incoming_retry),

    override("Endpoint", :bind, :singleton, 1, :uniffi_iroh_ffi_fn_constructor_endpoint_bind),
    override("Endpoint", :accept_next, :instance, 0, :uniffi_iroh_ffi_fn_method_endpoint_accept_next),
    override("Endpoint", :add_external_addr, :instance, 1, :uniffi_iroh_ffi_fn_method_endpoint_add_external_addr),
    override("Endpoint", :close, :instance, 0, :uniffi_iroh_ffi_fn_method_endpoint_close),
    override("Endpoint", :connect, :instance, 2, :uniffi_iroh_ffi_fn_method_endpoint_connect),
    override("Endpoint", :connect_pending, :instance, 2, :uniffi_iroh_ffi_fn_method_endpoint_connect_pending),
    override("Endpoint", :insert_relay, :instance, 1, :uniffi_iroh_ffi_fn_method_endpoint_insert_relay),
    override("Endpoint", :online, :instance, 0, :uniffi_iroh_ffi_fn_method_endpoint_online),
    override("Endpoint", :remote_addr, :instance, 1, :uniffi_iroh_ffi_fn_method_endpoint_remote_addr),
    override("Endpoint", :remove_external_addr, :instance, 1, :uniffi_iroh_ffi_fn_method_endpoint_remove_external_addr),
    override("Endpoint", :remove_relay, :instance, 1, :uniffi_iroh_ffi_fn_method_endpoint_remove_relay),

    override("Connection", :accept_bi, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_accept_bi),
    override("Connection", :accept_uni, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_accept_uni),
    override("Connection", :closed, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_closed),
    override("Connection", :open_bi, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_open_bi),
    override("Connection", :open_uni, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_open_uni),
    override("Connection", :read_datagram, :instance, 0, :uniffi_iroh_ffi_fn_method_connection_read_datagram),
    override("Connection", :send_datagram_wait, :instance, 1,
             :uniffi_iroh_ffi_fn_method_connection_send_datagram_wait),

    override("RecvStream", :bytes_read, :instance, 0, :uniffi_iroh_ffi_fn_method_recvstream_bytes_read),
    override("RecvStream", :id, :instance, 0, :uniffi_iroh_ffi_fn_method_recvstream_id),
    override("RecvStream", :read, :instance, 1, :uniffi_iroh_ffi_fn_method_recvstream_read),
    override("RecvStream", :read_exact, :instance, 1, :uniffi_iroh_ffi_fn_method_recvstream_read_exact),
    override("RecvStream", :read_to_end, :instance, 1, :uniffi_iroh_ffi_fn_method_recvstream_read_to_end),
    override("RecvStream", :received_reset, :instance, 0, :uniffi_iroh_ffi_fn_method_recvstream_received_reset),
    override("RecvStream", :stop, :instance, 1, :uniffi_iroh_ffi_fn_method_recvstream_stop),

    override("SendStream", :finish, :instance, 0, :uniffi_iroh_ffi_fn_method_sendstream_finish),
    override("SendStream", :id, :instance, 0, :uniffi_iroh_ffi_fn_method_sendstream_id),
    override("SendStream", :priority, :instance, 0, :uniffi_iroh_ffi_fn_method_sendstream_priority),
    override("SendStream", :reset, :instance, 1, :uniffi_iroh_ffi_fn_method_sendstream_reset),
    override("SendStream", :set_priority, :instance, 1, :uniffi_iroh_ffi_fn_method_sendstream_set_priority),
    override("SendStream", :stopped, :instance, 0, :uniffi_iroh_ffi_fn_method_sendstream_stopped),
    override("SendStream", :write, :instance, 1, :uniffi_iroh_ffi_fn_method_sendstream_write),
    override("SendStream", :write_all, :instance, 1, :uniffi_iroh_ffi_fn_method_sendstream_write_all),

    override("ServicesClient", :create, :singleton, 2, :uniffi_iroh_ffi_fn_constructor_servicesclient_create),
    override("ServicesClient", :name, :instance, 0, :uniffi_iroh_ffi_fn_method_servicesclient_name),
    override("ServicesClient", :ping, :instance, 0, :uniffi_iroh_ffi_fn_method_servicesclient_ping),
    override("ServicesClient", :push_metrics, :instance, 0, :uniffi_iroh_ffi_fn_method_servicesclient_push_metrics),
    override("ServicesClient", :set_name, :instance, 1, :uniffi_iroh_ffi_fn_method_servicesclient_set_name),
    override("ServicesClient", :submit_network_diagnostics, :instance, 1,
             :uniffi_iroh_ffi_fn_method_servicesclient_submit_network_diagnostics),

    override("WatchHandle", :stop, :instance, 0, :uniffi_iroh_ffi_fn_method_watchhandle_stop)
  ].freeze

  def self.install!
    with_redefinition_warnings_suppressed do
      patch_accepting
      patch_connecting
      patch_incoming
      patch_endpoint
      patch_connection
      patch_recv_stream
      patch_send_stream
      patch_services_client
      patch_watch_handle
    end
  end

  def self.with_redefinition_warnings_suppressed
    previous_verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous_verbose
  end

  def self.patch_accepting
    IrohFfi::Accepting.class_eval do
      def alpn
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_accepting_alpn,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def connect
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_accepting_connect,
                                              uniffi_clone_handle)
        IrohFfi::Connection.uniffi_allocate(Iroh::Async.await_u64(future))
      end
    end
  end

  def self.patch_connecting
    IrohFfi::Connecting.class_eval do
      def alpn
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connecting_alpn,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def connect
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connecting_connect,
                                              uniffi_clone_handle)
        IrohFfi::Connection.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def remote_id
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connecting_remote_id,
                                              uniffi_clone_handle)
        IrohFfi::EndpointId.uniffi_allocate(Iroh::Async.await_u64(future))
      end
    end
  end

  def self.patch_incoming
    IrohFfi::Incoming.class_eval do
      def accept
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_accept,
                                              uniffi_clone_handle)
        IrohFfi::Accepting.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def ignore
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_ignore,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def local_addr
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_local_addr,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoTypeIncomingLocalAddr
      end

      def refuse
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_refuse,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def remote_addr
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_remote_addr,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoTypeIncomingAddr
      end

      def remote_addr_validated
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError,
                                              :uniffi_iroh_ffi_fn_method_incoming_remote_addr_validated,
                                              uniffi_clone_handle)
        Iroh::Async.await_i8(future) == 1
      end

      def retry
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_incoming_retry,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end
    end
  end

  def self.patch_endpoint
    IrohFfi::Endpoint.class_eval do
      def self.bind(options)
        RustBuffer.check_lower_TypeEndpointOptions(options)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_constructor_endpoint_bind,
                                              RustBuffer.alloc_from_TypeEndpointOptions(options))
        uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def accept_next
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_endpoint_accept_next, uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future, error: nil).consumeIntoOptionalTypeIncoming
      end

      def add_external_addr(addr)
        addr = IrohFfi.uniffi_utf8(addr)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_add_external_addr,
                                              uniffi_clone_handle, RustBuffer.allocFromString(addr))
        Iroh::Async.await_void(future)
      end

      def close
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_close,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def connect(addr, alpn)
        IrohFfi::EndpointAddr.uniffi_check_lower(addr)
        alpn = IrohFfi.uniffi_bytes(alpn)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_connect,
                                              uniffi_clone_handle, IrohFfi::EndpointAddr.uniffi_lower(addr),
                                              RustBuffer.allocFromBytes(alpn))
        IrohFfi::Connection.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def connect_pending(addr, alpn)
        IrohFfi::EndpointAddr.uniffi_check_lower(addr)
        alpn = IrohFfi.uniffi_bytes(alpn)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_connect_pending,
                                              uniffi_clone_handle, IrohFfi::EndpointAddr.uniffi_lower(addr),
                                              RustBuffer.allocFromBytes(alpn))
        IrohFfi::Connecting.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def insert_relay(config)
        RustBuffer.check_lower_TypeRelayConfig(config)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_insert_relay,
                                              uniffi_clone_handle, RustBuffer.alloc_from_TypeRelayConfig(config))
        Iroh::Async.await_void(future)
      end

      def online
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_endpoint_online, uniffi_clone_handle)
        Iroh::Async.await_void(future, error: nil)
      end

      def remote_addr(id)
        IrohFfi::EndpointId.uniffi_check_lower(id)
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_endpoint_remote_addr,
                                   uniffi_clone_handle, IrohFfi::EndpointId.uniffi_lower(id))
        Iroh::Async.await_rust_buffer(future, error: nil).consumeIntoOptionalTypeEndpointAddr
      end

      def remove_external_addr(addr)
        addr = IrohFfi.uniffi_utf8(addr)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError,
                                              :uniffi_iroh_ffi_fn_method_endpoint_remove_external_addr,
                                              uniffi_clone_handle, RustBuffer.allocFromString(addr))
        Iroh::Async.await_i8(future) == 1
      end

      def remove_relay(url)
        url = IrohFfi.uniffi_utf8(url)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_endpoint_remove_relay,
                                              uniffi_clone_handle, RustBuffer.allocFromString(url))
        Iroh::Async.await_i8(future) == 1
      end
    end
  end

  def self.patch_connection
    IrohFfi::Connection.class_eval do
      def accept_bi
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connection_accept_bi,
                                              uniffi_clone_handle)
        IrohFfi::BiStream.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def accept_uni
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connection_accept_uni,
                                              uniffi_clone_handle)
        IrohFfi::RecvStream.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def closed
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_connection_closed, uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future, error: nil).consumeIntoString
      end

      def open_bi
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connection_open_bi,
                                              uniffi_clone_handle)
        IrohFfi::BiStream.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def open_uni
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connection_open_uni,
                                              uniffi_clone_handle)
        IrohFfi::SendStream.uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def read_datagram
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_connection_read_datagram,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def send_datagram_wait(data)
        data = IrohFfi.uniffi_bytes(data)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError,
                                              :uniffi_iroh_ffi_fn_method_connection_send_datagram_wait,
                                              uniffi_clone_handle, RustBuffer.allocFromBytes(data))
        Iroh::Async.await_void(future)
      end
    end
  end

  def self.patch_recv_stream
    IrohFfi::RecvStream.class_eval do
      def bytes_read
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_recvstream_bytes_read,
                                              uniffi_clone_handle)
        Iroh::Async.await_u64(future)
      end

      def id
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_recvstream_id, uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future, error: nil).consumeIntoString
      end

      def read(size_limit)
        size_limit = IrohFfi.uniffi_in_range(size_limit, "u32", 0, 2**32)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_recvstream_read,
                                              uniffi_clone_handle, size_limit)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def read_exact(size)
        size = IrohFfi.uniffi_in_range(size, "u32", 0, 2**32)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_recvstream_read_exact,
                                              uniffi_clone_handle, size)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def read_to_end(size_limit)
        size_limit = IrohFfi.uniffi_in_range(size_limit, "u32", 0, 2**32)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_recvstream_read_to_end,
                                              uniffi_clone_handle, size_limit)
        Iroh::Async.await_rust_buffer(future).consumeIntoBytes
      end

      def received_reset
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError,
                                              :uniffi_iroh_ffi_fn_method_recvstream_received_reset,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoOptionalu64
      end

      def stop(error_code)
        error_code = IrohFfi.uniffi_in_range(error_code, "u64", 0, 2**64)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_recvstream_stop,
                                              uniffi_clone_handle, error_code)
        Iroh::Async.await_void(future)
      end
    end
  end

  def self.patch_send_stream
    IrohFfi::SendStream.class_eval do
      def finish
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_finish,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def id
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_sendstream_id, uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future, error: nil).consumeIntoString
      end

      def priority
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_priority,
                                              uniffi_clone_handle)
        Iroh::Async.await_i32(future)
      end

      def reset(error_code)
        error_code = IrohFfi.uniffi_in_range(error_code, "u64", 0, 2**64)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_reset,
                                              uniffi_clone_handle, error_code)
        Iroh::Async.await_void(future)
      end

      def set_priority(p)
        p = IrohFfi.uniffi_in_range(p, "i32", -(2**31), 2**31)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_set_priority,
                                              uniffi_clone_handle, p)
        Iroh::Async.await_void(future)
      end

      def stopped
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_stopped,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoOptionalu64
      end

      def write(buf)
        buf = IrohFfi.uniffi_bytes(buf)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_write,
                                              uniffi_clone_handle, RustBuffer.allocFromBytes(buf))
        Iroh::Async.await_u64(future)
      end

      def write_all(buf)
        buf = IrohFfi.uniffi_bytes(buf)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_sendstream_write_all,
                                              uniffi_clone_handle, RustBuffer.allocFromBytes(buf))
        Iroh::Async.await_void(future)
      end
    end
  end

  def self.patch_services_client
    IrohFfi::ServicesClient.class_eval do
      def self.create(endpoint, options)
        IrohFfi::Endpoint.uniffi_check_lower(endpoint)
        RustBuffer.check_lower_TypeServicesOptions(options)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_constructor_servicesclient_create,
                                              IrohFfi::Endpoint.uniffi_lower(endpoint),
                                              RustBuffer.alloc_from_TypeServicesOptions(options))
        uniffi_allocate(Iroh::Async.await_u64(future))
      end

      def name
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_servicesclient_name,
                                              uniffi_clone_handle)
        Iroh::Async.await_rust_buffer(future).consumeIntoOptionalstring
      end

      def ping
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_servicesclient_ping,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def push_metrics
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_servicesclient_push_metrics,
                                              uniffi_clone_handle)
        Iroh::Async.await_void(future)
      end

      def set_name(name)
        name = IrohFfi.uniffi_utf8(name)
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError, :uniffi_iroh_ffi_fn_method_servicesclient_set_name,
                                              uniffi_clone_handle, RustBuffer.allocFromString(name))
        Iroh::Async.await_void(future)
      end

      def submit_network_diagnostics(send)
        send = send ? true : false
        future = IrohFfi.rust_call_with_error(IrohFfi::IrohError,
                                              :uniffi_iroh_ffi_fn_method_servicesclient_submit_network_diagnostics,
                                              uniffi_clone_handle, (send ? 1 : 0))
        Iroh::Async.await_rust_buffer(future).consumeIntoTypeDiagnosticsSummary
      end
    end
  end

  def self.patch_watch_handle
    IrohFfi::WatchHandle.class_eval do
      def stop
        future = IrohFfi.rust_call(:uniffi_iroh_ffi_fn_method_watchhandle_stop, uniffi_clone_handle)
        Iroh::Async.await_void(future, error: nil)
      end
    end
  end
end

IrohFfiAsyncPatches.install!
