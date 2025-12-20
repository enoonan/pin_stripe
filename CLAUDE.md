# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PinStripe is a minimalist Stripe integration library for Elixir built on three core pillars:

1. **Simple API Client** (`PinStripe.Client`) - Built on Req with automatic Stripe ID prefix recognition
2. **Webhook Handler DSL** (`PinStripe.WebhookController`) - Declarative webhook handling using Spark
3. **Testing Utilities** (`PinStripe.Test.*`) - Mock helpers and fixtures for testing Stripe integrations

The library emphasizes simplicity over completeness, targeting 95% of use cases while providing an escape hatch to Req for advanced scenarios.

## Development Commands

### Testing
```bash
# Run all tests
mix test

# Run a specific test file
mix test test/client_test.exs

# Run a specific test by line number
mix test test/client_test.exs:42

# Run tests with coverage
mix test --cover
```

### Code Quality
```bash
# Run Credo for code analysis
mix credo

# Check for security issues with Sobelow
mix sobelow

# Format code
mix format
```

### Library-Specific Tasks
```bash
# Generate a webhook handler
mix pin_stripe.gen.handler customer.created

# Sync handlers with Stripe dashboard
mix pin_stripe.sync_webhook_handlers

# Sync fixture API version
mix pin_stripe.sync_api_version

# Update supported events list (contributors only)
mix pin_stripe.update_supported_events
```

### Dependencies
```bash
mix deps.get      # Fetch dependencies
mix deps.compile  # Compile dependencies
mix compile       # Compile the project
```

## Architecture

### Spark DSL Integration

The webhook handler system is built on **Spark**, a DSL framework. Key architectural components:

- **`PinStripe.WebhookHandler.Dsl`**: Defines the `handle/2` DSL entity that accepts event types and handlers
- **`PinStripe.WebhookHandler.Transformers.GenerateHandleEvent`**: Spark transformer that generates the `handle_event/2` function at compile time from DSL declarations
- **`PinStripe.WebhookHandler.Info`**: Provides reflection APIs to query handlers defined via DSL

When users write `handle "customer.created", fn -> :ok end`, Spark transforms this into a runtime dispatch function. This pattern keeps controllers clean and declarative.

### Request Body Caching Architecture

**Critical webhook requirement**: Stripe signature verification requires the exact raw request body bytes.

**Solution**: `PinStripe.ParsersWithRawBody` is a custom Plug.Parsers that:
- Selectively caches raw body chunks only for configured webhook paths (stored in `conn.assigns.raw_body`)
- For all other routes, behaves like standard Plug.Parsers (no memory overhead)
- Reads `webhook_paths` from application config to determine when to cache

**Why this approach?**: Standard body parsers consume the request body. Signature verification requires access to unparsed bytes, necessitating custom caching before parsing occurs.

### Client Architecture

`PinStripe.Client` wraps Req with Stripe-specific conventions:

- **ID prefix recognition**: Automatically routes `cus_123` to `/customers/cus_123` based on prefix patterns
- **Entity atoms**: Maps `:customers`, `:subscriptions`, etc. to API paths
- **Dual interfaces**: Both `{:ok, response}` tuples and bang variants (`read!`, `create!`, etc.)
- **Req integration**: Returns `Req.Response` structs directly, providing escape hatch for advanced Req usage

The `new/1` function builds a configured Req client with:
- Base URL and auth header pre-configured
- Optional test adapter injection via `:req_options` config
- Custom request step to convert GET-with-body to POST (Stripe convention)

### Testing Architecture

Two-tier testing approach:

1. **Mock helpers** (`PinStripe.Test.Mock`): High-level stubbing for common operations
   - `stub_read/2`, `stub_create/2`, `stub_update/2`, `stub_delete/2`, `stub_error/3`
   - Uses Req.Test under the hood
   - Requires `req_options: [plug: {Req.Test, PinStripe}]` in test config

2. **Fixtures** (`PinStripe.Test.Fixtures`): Two types of fixtures
   - **Error fixtures**: Pre-built in-memory (e.g., `:error_404`)
   - **API resource fixtures**: Generated once via Stripe CLI, cached in `test/support/fixtures/`
   - Fixtures are versioned by Stripe API version

**Key insight**: API fixtures create real test data in Stripe once, then cache JSON responses. This provides realistic test data without API calls per test run.

## Code Organization

```
lib/
├── pin_stripe.ex                    # Main module and documentation entry point
├── client.ex                        # Stripe API client (Req wrapper)
├── webhook_controller.ex            # Phoenix controller macro with signature verification
├── webhook_handler.ex               # Spark DSL for defining event handlers
├── webhook_handler/
│   ├── dsl.ex                      # DSL entity definitions
│   ├── info.ex                     # DSL reflection API
│   └── transformers/               # Spark compile-time transformers
├── webhook_signature.ex             # HMAC signature verification
├── parsers_with_raw_body.ex        # Custom Plug.Parsers for webhook bodies
├── test/
│   ├── mock.ex                     # Test stubbing helpers
│   └── fixtures.ex                 # Fixture loader and generator
└── mix/tasks/                      # Igniter-powered code generators
```

## Configuration Patterns

### Runtime Configuration
The library expects runtime configuration (typically in `config/runtime.exs`):

```elixir
config :pin_stripe,
  stripe_api_key: System.get_env("STRIPE_SECRET_KEY"),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET"),
  webhook_paths: ["/webhooks/stripe"]
```

### Test Configuration
Test environment requires Req.Test setup:

```elixir
config :pin_stripe,
  stripe_api_key: "sk_test_123",
  req_options: [plug: {Req.Test, PinStripe}]
```

### Multiple Webhook Endpoints
The `webhook_paths` config accepts a list to support multiple endpoints (e.g., regular Stripe + Connect).

## Formatter Configuration

The project uses Spark.Formatter plugin to properly format DSL declarations. The `.formatter.exs` exports `locals_without_parens: [handle: 2]` so that consuming applications can also format webhook controller DSL correctly.

## Dependencies of Note

- **Req**: Modern HTTP client, provides the foundation for API calls and testing
- **Spark**: DSL framework used for declarative webhook handlers
- **Igniter**: Code generation and modification engine for Mix tasks
- **Phoenix**: Optional dependency for webhook controller functionality

## When Modifying Webhook Handling

If you modify webhook handler DSL or transformers:
1. Changes to `PinStripe.WebhookHandler.Dsl` affect compile-time behavior
2. Test with `mix test test/webhook_controller_test.exs`
3. Verify DSL reflection works: `PinStripe.WebhookHandler.Info.handlers(module)`

## When Modifying Client

If you add new Stripe resource types:
1. Add ID prefix pattern to `parse_url/1` (e.g., `def parse_url("pi_" <> _ = id), do: "/payment_intents/#{id}"`)
2. Add entity atom to `entity_to_path/1` (e.g., `def entity_to_path(:payment_intents), do: {:ok, "/payment_intents"}`)
3. Update module documentation with new supported types
4. Add test cases in `test/client_test.exs`

## When Modifying Igniter Tasks

The Mix tasks in `lib/mix/tasks/` use Igniter for surgical code modifications:
- They operate on AST level, not string manipulation
- Changes are atomic and can be previewed before applying
- Tasks should be idempotent (safe to run multiple times)

## Version Compatibility

- Elixir: ~> 1.19
- Phoenix: ~> 1.7 (optional)
- Stripe API: Version agnostic, but fixtures are versioned
