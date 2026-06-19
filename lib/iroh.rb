# frozen_string_literal: true

require_relative "iroh/version"
require_relative "iroh/native"
require_relative "iroh/generated/iroh_ffi"
require_relative "iroh/async"

module Iroh
  PUBLIC_CONSTANTS = %i[
    Accepting
    AddrChangeCallback
    AddrChangeRecorder
    BiStream
    CallbackError
    Connecting
    Connection
    ConnectionStats
    CounterStats
    DiagnosticsSummary
    Endpoint
    EndpointAddr
    EndpointBuilder
    EndpointId
    EndpointOptions
    EndpointTicket
    Error
    HomeRelayCallback
    HomeRelayRecorder
    Incoming
    IncomingAddr
    IncomingLocalAddr
    LogLevel
    NetworkChangeCallback
    NetworkChangeRecorder
    PathChangeCallback
    PathEvent
    PathEventCallback
    PathSnapshot
    PathStatsRecord
    Preset
    ProtocolCreator
    ProtocolHandler
    ProtocolRouterEchoRecorder
    RecvStream
    RelayConfig
    RelayMap
    RelayMode
    SecretKey
    SendStream
    ServicesClient
    ServicesOptions
    Side
    Signature
    WatchHandle
  ].freeze

  IrohFfi.constants.each do |name|
    target_name = name == :IrohError ? :Error : name
    next unless PUBLIC_CONSTANTS.include?(target_name)
    next if const_defined?(target_name, false)

    const_set(target_name, IrohFfi.const_get(name))
  end

  DISPLAY_METHODS = {
    EndpointAddr => :uniffi_iroh_ffi_fn_method_endpointaddr_uniffi_trait_display,
    EndpointId => :uniffi_iroh_ffi_fn_method_endpointid_uniffi_trait_display,
    EndpointTicket => :uniffi_iroh_ffi_fn_method_endpointticket_uniffi_trait_display,
    RelayMap => :uniffi_iroh_ffi_fn_method_relaymap_uniffi_trait_display,
    RelayMode => :uniffi_iroh_ffi_fn_method_relaymode_uniffi_trait_display,
    Signature => :uniffi_iroh_ffi_fn_method_signature_uniffi_trait_display
  }.freeze

  DISPLAY_METHODS.each do |klass, function_name|
    klass.define_method(:to_string) do
      IrohFfi.rust_call(function_name, uniffi_clone_handle).consumeIntoString
    end

    klass.alias_method :to_s, :to_string
  end

  module_function

  def preset_minimal
    IrohFfi.preset_minimal
  end

  def preset_n0
    IrohFfi.preset_n0
  end

  def preset_n0_disable_relay
    IrohFfi.preset_n0_disable_relay
  end

  def set_log_level(level)
    IrohFfi.set_log_level(level)
  end
end
