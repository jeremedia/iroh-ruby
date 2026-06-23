# Changelog

## Unreleased

### 0.1.0 release readiness

- Added a real Ruby gem scaffold for `iroh-ffi` 1.0.0 with generated UniFFI
  bindings, a Ruby async bridge, native extension build hooks, and isolated
  installed-gem smoke verification.
- Proved endpoint, ticket, stream, datagram, telemetry, watcher, protocol
  router, `iroh-services`, and JSON command bridge workflows through runnable
  examples and Minitest coverage.
- Added release-hardening checks for handwritten async override drift and public
  API inventory drift.
- Added `release:smoke` as the local release-readiness gate across tests, demos,
  packaged install verification, and whitespace checks.
