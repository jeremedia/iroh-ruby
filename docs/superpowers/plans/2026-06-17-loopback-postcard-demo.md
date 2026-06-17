# Loopback Postcard Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a first working demo that proves the Ruby `iroh` gem can move a text payload between two local Iroh endpoints over a real connection.

**Architecture:** Add a reusable `Iroh::Examples::PostcardDemo` helper that owns endpoint setup, connection orchestration, one unidirectional stream write/read, and cleanup. Add a thin `examples/postcard.rb` script plus a `rake demo:postcard` task so humans can run the demo from a checkout.

**Tech Stack:** Ruby 3.2+, Minitest, Rake, generated UniFFI Ruby bindings, vendored Rust `iroh-ffi` native library.

---

## File Structure

- Create `examples/support/postcard_demo.rb`
  - Defines `Iroh::Examples::PostcardDemo`.
  - Exposes `deliver(message = DEFAULT_MESSAGE)`.
  - Returns a small result struct containing sender id, receiver id, ALPN, payload, and endpoint closed flags.
  - Owns endpoint cleanup in one place.
- Create `examples/postcard.rb`
  - Human-facing executable script.
  - Parses `ARGV`, calls `PostcardDemo.deliver`, prints a compact transcript, exits nonzero on failure.
- Create `test/iroh_postcard_demo_test.rb`
  - Integration test for one local message delivery.
  - Calls the helper directly instead of shelling out.
- Modify `Rakefile`
  - Add `demo:postcard` task depending on `native:build`.
- Modify `iroh.gemspec`
  - Include `examples/**/*.rb` in packaged gem files.
- Modify `README.md`
  - Document the demo command and expected output shape.

## Task 1: Add Failing Integration Test

**Files:**
- Create: `test/iroh_postcard_demo_test.rb`
- No production implementation yet.

- [ ] **Step 1: Write the failing test**

Create `test/iroh_postcard_demo_test.rb`:

```ruby
# frozen_string_literal: true

require "test_helper"
require_relative "../examples/support/postcard_demo"

class IrohPostcardDemoTest < Minitest::Test
  def test_delivers_text_payload_between_loopback_endpoints
    message = "hello from ruby iroh"

    result = Iroh::Examples::PostcardDemo.deliver(message)

    assert_equal message, result.payload
    assert_equal "iroh-ruby/demo/postcard", result.alpn
    refute_empty result.sender_id
    refute_empty result.receiver_id
    assert result.sender_closed
    assert result.receiver_closed
  end
end
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run:

```bash
bundle exec ruby -Itest test/iroh_postcard_demo_test.rb
```

Expected result:

```text
LoadError with a message containing examples/support/postcard_demo
```

If the test passes, stop and inspect whether `examples/support/postcard_demo.rb`
already exists. The RED state must prove the helper is missing.

- [ ] **Step 3: Commit the failing test only**

Do not commit this step unless the test has failed for the expected missing-file
reason.

```bash
git add test/iroh_postcard_demo_test.rb
git commit -m "test: add postcard demo integration coverage"
```

## Task 2: Implement the Loopback Demo Helper

**Files:**
- Create: `examples/support/postcard_demo.rb`
- Test: `test/iroh_postcard_demo_test.rb`

- [ ] **Step 1: Add the helper implementation**

Create `examples/support/postcard_demo.rb`:

```ruby
# frozen_string_literal: true

require "thread"
require "iroh"

module Iroh
  module Examples
    module PostcardDemo
      ALPN = "iroh-ruby/demo/postcard"
      DEFAULT_MESSAGE = "hello from ruby iroh"
      MAX_PAYLOAD_BYTES = 1_048_576

      Result = Struct.new(
        :sender_id,
        :receiver_id,
        :alpn,
        :payload,
        :sender_closed,
        :receiver_closed,
        keyword_init: true
      )

      module_function

      def deliver(message = DEFAULT_MESSAGE)
        message = normalize_message(message)
        receiver = bind_endpoint
        sender = bind_endpoint
        receiver_queue = Queue.new

        receiver_thread = Thread.new do
          receive_one_message(receiver, receiver_queue)
        end

        sender_connection = sender.connect(receiver.addr, ALPN)
        send_stream = sender_connection.open_uni
        send_stream.write_all(message)
        send_stream.finish

        status, value = receiver_queue.pop
        receiver_thread.join
        raise value if status == :error

        sender_id = sender.id.to_s
        receiver_id = receiver.id.to_s

        close_endpoint(sender)
        close_endpoint(receiver)

        Result.new(
          sender_id: sender_id,
          receiver_id: receiver_id,
          alpn: ALPN,
          payload: value,
          sender_closed: sender.is_closed,
          receiver_closed: receiver.is_closed
        )
      ensure
        close_endpoint(sender)
        close_endpoint(receiver)
        receiver_thread&.join(2)
      end

      def bind_endpoint
        Iroh::Endpoint.bind(
          Iroh::EndpointOptions.new(
            preset: Iroh.preset_minimal,
            relay_mode: Iroh::RelayMode.disabled,
            bind_addr: "127.0.0.1:0",
            alpns: [ALPN]
          )
        )
      end

      def receive_one_message(receiver, receiver_queue)
        incoming = receiver.accept_next
        raise "receiver endpoint closed before accepting a connection" unless incoming

        accepting = incoming.accept
        receiver_connection = accepting.connect
        recv_stream = receiver_connection.accept_uni
        payload = recv_stream.read_to_end(MAX_PAYLOAD_BYTES)

        receiver_queue << [:ok, normalize_payload(payload)]
      rescue StandardError => e
        receiver_queue << [:error, e]
      end

      def normalize_message(message)
        message.to_s.encode(Encoding::UTF_8)
      end

      def normalize_payload(payload)
        payload = payload.to_s
        payload.force_encoding(Encoding::UTF_8)
        payload
      end

      def close_endpoint(endpoint)
        return unless endpoint
        return if endpoint.is_closed

        endpoint.close
      rescue StandardError
        nil
      end
    end
  end
end
```

- [ ] **Step 2: Run the focused integration test**

Run:

```bash
bundle exec ruby -Itest test/iroh_postcard_demo_test.rb
```

Expected result:

```text
1 runs, 6 assertions, 0 failures, 0 errors, 0 skips
```

If the test hangs, interrupt it and inspect whether `receiver.accept_next` is
waiting because `sender.connect(receiver.addr, ALPN)` failed before dialing.
Do not add sleeps as the first fix; inspect the raised exception from the sender
side and the receiver queue path.

- [ ] **Step 3: Run the full test suite**

Run:

```bash
bundle exec rake test
```

Expected result includes:

```text
9 runs
0 failures, 0 errors, 0 skips
```

The exact assertion count may change if implementation details require another
assertion. Do not accept any failure or warning caused by the new demo code.

- [ ] **Step 4: Commit helper implementation**

```bash
git add examples/support/postcard_demo.rb test/iroh_postcard_demo_test.rb
git commit -m "feat: add loopback postcard demo helper"
```

## Task 3: Add Human-Facing Demo Script and Rake Task

**Files:**
- Create: `examples/postcard.rb`
- Modify: `Rakefile`
- Test manually with: `bundle exec ruby examples/postcard.rb "hello from ruby iroh"`

- [ ] **Step 1: Add the demo script**

Create `examples/postcard.rb`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require_relative "support/postcard_demo"

begin
  message = ARGV.empty? ? Iroh::Examples::PostcardDemo::DEFAULT_MESSAGE : ARGV.join(" ")
  result = Iroh::Examples::PostcardDemo.deliver(message)

  puts "iroh-ruby postcard demo"
  puts "sender:   #{result.sender_id}"
  puts "receiver: #{result.receiver_id}"
  puts "alpn:     #{result.alpn}"
  puts "payload:  #{result.payload}"
  puts "success:  delivered #{result.payload.bytesize} bytes over loopback"
rescue StandardError => e
  warn "postcard failed: #{e.message}"
  exit 1
end
```

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x examples/postcard.rb
```

- [ ] **Step 3: Add the Rake demo task**

Modify `Rakefile` by inserting this block before `task test: "native:build"`:

```ruby
namespace :demo do
  desc "Run the loopback postcard demo"
  task postcard: "native:build" do
    ruby "examples/postcard.rb", "hello from ruby iroh"
  end
end
```

The end of `Rakefile` must become:

```ruby
namespace :demo do
  desc "Run the loopback postcard demo"
  task postcard: "native:build" do
    ruby "examples/postcard.rb", "hello from ruby iroh"
  end
end

task test: "native:build"
task default: :test
```

- [ ] **Step 4: Run the script manually**

Run:

```bash
bundle exec ruby examples/postcard.rb "hello from ruby iroh"
```

Expected output shape:

```text
iroh-ruby postcard demo
sender:   <non-empty endpoint id>
receiver: <non-empty endpoint id>
alpn:     iroh-ruby/demo/postcard
payload:  hello from ruby iroh
success:  delivered 20 bytes over loopback
```

- [ ] **Step 5: Run the Rake task**

Run:

```bash
bundle exec rake demo:postcard
```

Expected output shape matches the manual script run.

- [ ] **Step 6: Commit the script and Rake task**

```bash
git add examples/postcard.rb Rakefile
git commit -m "feat: add postcard demo runner"
```

## Task 4: Package and Document the Demo

**Files:**
- Modify: `iroh.gemspec`
- Modify: `README.md`
- Test: gem build plus package file listing

- [ ] **Step 1: Include examples in gem package**

Modify the `spec.files` list in `iroh.gemspec` so it includes examples:

```ruby
      "lib/**/*.rb",
      "examples/**/*.rb",
      "ext/**/*",
```

- [ ] **Step 2: Add README demo documentation**

Add this section to `README.md` after the usage example:

````markdown
## Demo

Run the loopback postcard demo from a source checkout:

```sh
bundle exec rake demo:postcard
```

Or pass a custom message:

```sh
bundle exec ruby examples/postcard.rb "hello from ruby iroh"
```

The demo starts two local endpoints with relays disabled, sends one payload over
a unidirectional stream, prints both endpoint ids, and closes both endpoints.
It is intentionally local-only so it can prove the Ruby binding and async bridge
without external service dependencies.
````

When inserting this Markdown, keep the nested shell fences exactly as shown.

- [ ] **Step 3: Verify the gem builds**

Run:

```bash
bundle exec gem build iroh.gemspec
```

Expected result:

```text
Successfully built RubyGem
Name: iroh
Version: 0.1.0
File: iroh-0.1.0.gem
```

- [ ] **Step 4: Verify examples are packaged**

Run:

```bash
gem specification ./iroh-0.1.0.gem files | rg 'examples/(postcard|support/postcard_demo)\\.rb'
```

Expected result:

```text
- examples/postcard.rb
- examples/support/postcard_demo.rb
```

- [ ] **Step 5: Commit package/docs changes**

```bash
git add iroh.gemspec README.md
git commit -m "docs: document postcard demo"
```

## Task 5: Final Verification and Push

**Files:**
- No new files.
- Verify the complete branch.

- [ ] **Step 1: Run full local verification**

Run:

```bash
bundle exec rake test
bundle exec rake demo:postcard
bundle exec gem build iroh.gemspec
```

Expected results:

```text
9 runs
0 failures, 0 errors, 0 skips
```

```text
success:  delivered 20 bytes over loopback
```

```text
Successfully built RubyGem
Name: iroh
Version: 0.1.0
File: iroh-0.1.0.gem
```

- [ ] **Step 2: Check staged and ignored artifacts**

Run:

```bash
git status --short --ignored
git ls-files | rg '\\.DS_Store|iroh-0\\.1\\.0\\.gem|lib/iroh/native|^tmp/|^\\.serena/' || true
```

Expected:

- `git status --short --ignored` may show ignored local build outputs such as
  `!! iroh-0.1.0.gem`, `!! lib/iroh/native/`, and `!! tmp/`.
- The `git ls-files | rg '\\.DS_Store|iroh-0\\.1\\.0\\.gem|lib/iroh/native|^tmp/|^\\.serena/' || true` command must print only `lib/iroh/native.rb`.

- [ ] **Step 3: Push commits**

Run:

```bash
git push
```

- [ ] **Step 4: Watch GitHub CI**

Run:

```bash
gh run list --repo jeremedia/iroh-ruby --limit 1
gh run watch <new-run-id> --repo jeremedia/iroh-ruby --exit-status --interval 10
```

Expected:

```text
conclusion: success
```

The CI matrix must pass on Ruby 3.2 and 3.4 across Ubuntu and macOS.
