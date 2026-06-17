# iroh

Ruby bindings for the [Iroh](https://www.iroh.computer/) networking project.

This gem wraps the upstream `iroh-ffi` 1.0 surface via UniFFI-generated Ruby
bindings and exposes the public API under the `Iroh` module.

## Status

The wrapped upstream crate is `iroh-ffi` 1.0.0, which tracks the Iroh 1.0 API
surface for endpoints, connections, streams, datagrams, endpoint IDs, endpoint
addresses, tickets, relays, watchers, multipath snapshots, and
`iroh-services`. The upstream FFI intentionally does not expose blobs, docs, or
gossip yet.

## Requirements

- Ruby 3.2+
- Rust 1.91+
- Cargo

Install dependencies and build the native library:

```sh
bundle install
bundle exec rake native:build
bundle exec rake test
```

If you already have a compatible `iroh_ffi` dynamic library, set
`IROH_FFI_LIBRARY=/absolute/path/to/libiroh_ffi.dylib` before requiring the gem.

## Usage

```ruby
require "iroh"

secret = Iroh::SecretKey.generate
signature = secret.sign("hello iroh")
secret.public.verify("hello iroh", signature)

endpoint = Iroh::Endpoint.bind(
  Iroh::EndpointOptions.new(
    preset: Iroh.preset_minimal,
    relay_mode: Iroh::RelayMode.disabled,
    bind_addr: "127.0.0.1:0"
  )
)

ticket = Iroh::EndpointTicket.from_addr(endpoint.addr)
puts ticket.to_s
endpoint.close
```

## Development

Regenerate the Ruby UniFFI binding after changing `vendor/iroh-ffi`:

```sh
bundle exec rake native:generate
```

Run tests:

```sh
bundle exec rake test
```
