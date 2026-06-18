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

## Demo

Run the postcard demo through Rake:

```sh
bundle exec rake demo:postcard
```

Or run it directly with a custom payload:

```sh
bundle exec ruby examples/postcard.rb "hello from ruby iroh"
```

The demo starts two local endpoints with relays disabled, sends one payload over
a unidirectional stream, prints endpoint ids, and closes both endpoints. It is
intentionally local-only to prove the Ruby binding and async bridge without
external service dependencies.

Run the ticket echo demo to exercise serialized endpoint tickets and
bidirectional streams:

```sh
bundle exec rake demo:ticket_echo
```

Or run it directly with a custom payload:

```sh
bundle exec ruby examples/ticket_echo.rb "hello from ticket land"
```

The demo creates an `EndpointTicket`, parses the serialized ticket back into an
endpoint address, opens a bidirectional stream, sends one payload, receives an
echo response, and closes both endpoints.

Run the datagram ping demo to exercise unordered datagram messages:

```sh
bundle exec rake demo:datagram_ping
```

Or run it directly with a custom payload:

```sh
bundle exec ruby examples/datagram_ping.rb "hello from datagram land"
```

The demo opens a local connection, sends one `ping:` datagram, receives one
`pong:` datagram, prints both endpoint ids, and closes both endpoints.

Run the ticket exchange demo to exercise a ticket across two Ruby processes:

```sh
bundle exec rake demo:ticket_exchange
```

For the manual two-terminal workflow, start the server first:

```sh
bundle exec ruby examples/ticket_server.rb
```

Copy the printed ticket into the client command:

```sh
bundle exec ruby examples/ticket_client.rb "<ticket>" "hello from another ruby process"
```

The server prints a serialized endpoint ticket before waiting for a client. The
client parses that ticket in a separate Ruby process, opens a bidirectional
stream, sends one payload, receives an echo response, and closes its endpoint.

Run the connection telemetry demo to inspect snapshot connection state:

```sh
bundle exec rake demo:connection_telemetry
```

Or run it directly with a custom payload:

```sh
bundle exec ruby examples/connection_telemetry.rb "hello from telemetry land"
```

The demo starts a server in a separate Ruby process, connects a client with the
printed endpoint ticket, exchanges one bidirectional stream payload, and prints
client and server telemetry snapshots before closing endpoints. It uses polling
snapshots such as connection stats, selected paths, RTT, and endpoint counters.
The `Endpoint#online` wait and watcher/callback APIs are left for later
threading-focused demos.

Run the protocol router demo to exercise router-backed ALPN dispatch:

```sh
bundle exec rake demo:protocol_router
```

Or run it directly with a custom payload:

```sh
bundle exec ruby examples/protocol_router.rb "hello from the protocol router"
```

The demo binds a server endpoint with `EndpointOptions#protocols`, registers a
native `ProtocolCreator` handle, connects a client with the matching ALPN, sends
one bidirectional stream request, receives a `routed:` response, and verifies
handler create, accept, and shutdown counts. Ruby-owned protocol callbacks are
not exposed by the current UniFFI Ruby generator, so this demo uses a
Rust-owned recorder object to prove the real router path.

## Development

Regenerate the Ruby UniFFI binding after changing `vendor/iroh-ffi`:

```sh
bundle exec rake native:generate
```

Run tests:

```sh
bundle exec rake test
```

Verify the packaged gem from an isolated consumer install:

```sh
bundle exec rake smoke:installed_gem
```

This builds the gem, installs it into a temporary `GEM_HOME`, runs Ruby outside
the repository checkout, requires `iroh`, checks bundled native library lookup,
and exercises a minimal key, endpoint, and ticket lifecycle.
