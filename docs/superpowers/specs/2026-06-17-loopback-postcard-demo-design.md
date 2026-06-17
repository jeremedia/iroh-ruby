# Loopback Postcard Demo Design

## Goal

Build the first visible demo for the `iroh` Ruby gem: a single-process loopback
program that starts two local Iroh endpoints, sends one text payload from one
endpoint to the other over a unidirectional stream, prints the result, and shuts
down cleanly.

## Success Criteria

- Running `bundle exec ruby examples/postcard.rb "hello from ruby iroh"` prints:
  - sender endpoint id
  - receiver endpoint id
  - the ALPN used for the connection
  - the received payload
  - a clear success line
- The demo uses only local loopback networking with relays disabled.
- The demo exercises real networking APIs, not only key generation or endpoint
  binding.
- The demo has an automated integration test that fails before the demo helper
  exists and passes after implementation.
- The demo is included in the gem package as an example file, while generated
  build outputs remain ignored.

## Architecture

The demo will have a small reusable helper module under `examples/support/` and
a thin executable script under `examples/postcard.rb`. The helper owns endpoint
creation, connection orchestration, stream write/read, and cleanup. The script
only parses the optional message argument, calls the helper, and formats output.

This structure keeps the integration test focused on a Ruby method instead of
shelling out to a script, while still giving humans a simple command to run.

## Data Flow

1. Bind a receiver endpoint with `Iroh.preset_minimal`, `RelayMode.disabled`,
   ALPN `iroh-ruby/demo/postcard`, and bind address `127.0.0.1:0`.
2. Bind a sender endpoint with the same relay-disabled local configuration.
3. Start a Ruby thread on the receiver side that calls `accept_next`, accepts
   the incoming handshake, waits for a connection, accepts one unidirectional
   stream, and reads the payload with `read_to_end`.
4. From the sender side, connect to `receiver.addr`, open one unidirectional
   stream, write the payload with `write_all`, and finish the stream.
5. Join the receiver thread, return a result object, and close both endpoints.

## Error Handling

The helper must close both endpoints in an `ensure` block even when connection
or stream operations fail. The thread body must let exceptions propagate back
to the caller by storing either the received payload or the exception in a
thread-local result container.

The script must catch `StandardError`, print `postcard failed: <message>` to
stderr, and exit nonzero.

## Testing

Add `test/iroh_postcard_demo_test.rb`. The first test must call the helper
directly with a message containing spaces and assert that:

- the returned payload exactly matches the input message
- sender and receiver endpoint ids are non-empty strings
- the ALPN equals `iroh-ruby/demo/postcard`
- both endpoints report closed at the end

Keep this as an integration test. It is intentionally heavier than the existing
unit tests because it proves the gem can move bytes across a real Iroh
connection from Ruby.

## Out Of Scope

- Two-process CLI mode.
- Relay-backed internet connectivity.
- Services diagnostics.
- File transfer.
- Packaging prebuilt native gems.
