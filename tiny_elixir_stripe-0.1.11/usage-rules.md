# TinyElixirStripe Usage Rules

A minimal Stripe SDK for Elixir with webhook handling, built on Req and Spark.

## Installation

Add to your `mix.exs`:

```elixir
{:tiny_elixir_stripe, "~> 0.1"}
```

Then run the installer:

```bash
mix igniter.install tiny_elixir_stripe
```

Or manually install:

```bash
mix tiny_elixir_stripe.install
```

## Configuration

Set your Stripe API key in `config/runtime.exs`:

```elixir
config :tiny_elixir_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  webhook_signing_secret: System.get_env("STRIPE_WEBHOOK_SECRET")
```

**Important**: Never commit API keys to version control. Always use environment variables.

## Making API Requests

Use `TinyElixirStripe.request/2` to make Stripe API calls:

```elixir
# GET request
{:ok, customer} = TinyElixirStripe.request(:get, "/v1/customers/cus_123")

# POST request with params
{:ok, customer} = TinyElixirStripe.request(:post, "/v1/customers", 
  email: "customer@example.com",
  name: "Jane Doe"
)

# DELETE request
{:ok, _} = TinyElixirStripe.request(:delete, "/v1/customers/cus_123")
```

All requests return `{:ok, response}` or `{:error, reason}` tuples.

## Webhook Handling

### WebhookHandler Module

The installer creates a `StripeWebhookHandlers` module. Define handlers using the DSL:

```elixir
defmodule MyApp.StripeWebhookHandlers do
  use TinyElixirStripe.WebhookHandler

  # Function handler - inline
  handle "customer.created", fn event ->
    customer = event.data.object
    # Handle the event
    :ok
  end

  # Module handler - separate module
  handle "invoice.paid", MyApp.InvoicePaidHandler
end
```

**Important**: 
- Always return `:ok` from handlers to acknowledge successful processing
- Return `{:error, reason}` to indicate processing failure (webhook will be retried by Stripe)
- The `event` parameter contains the full Stripe event object

### Handler Types

**Function Handlers** - Quick inline handlers:
```elixir
handle "customer.updated", fn event ->
  # Process event inline
  :ok
end
```

**Module Handlers** - Better for complex logic:
```elixir
# In your WebhookHandler module
handle "subscription.created", MyApp.SubscriptionCreatedHandler

# Separate module
defmodule MyApp.SubscriptionCreatedHandler do
  def handle_event(event) do
    subscription = event.data.object
    # Complex processing logic
    :ok
  end
end
```

### Generating Handlers

Use the generator to create handlers quickly:

```bash
# Generate a function handler
mix tiny_elixir_stripe.gen.handler customer.subscription.updated

# Generate a module handler
mix tiny_elixir_stripe.gen.handler invoice.paid --handler-type module
```

### Webhook Controller

The installer creates `lib/my_app_web/stripe_webhook_controller.ex` which:
- Verifies webhook signatures automatically
- Routes events to your handlers
- Handles errors gracefully

**Note**: The controller is created in `lib/my_app_web/`, not in `lib/my_app_web/controllers/`. You can move it to the controllers directory if preferred.

### Security

The installer configures `TinyElixirStripe.ParsersWithRawBody` in your endpoint, which:
- Caches the raw request body for signature verification
- Is required for Stripe webhook security
- Replaces the standard `Plug.Parsers`

**Critical**: Never skip webhook signature verification in production. The installer handles this automatically.

## Common Patterns

### Idempotent Webhook Processing

Stripe may send the same webhook multiple times. Make your handlers idempotent:

```elixir
handle "payment_intent.succeeded", fn event ->
  payment_intent_id = event.data.object.id
  
  # Check if already processed
  case MyApp.Payments.get_by_stripe_id(payment_intent_id) do
    nil -> 
      # First time, process it
      MyApp.Payments.create_from_stripe(event.data.object)
      :ok
    _existing -> 
      # Already processed, skip
      :ok
  end
end
```

### Error Handling

Return errors to have Stripe retry:

```elixir
handle "invoice.payment_failed", fn event ->
  case MyApp.Billing.handle_failed_payment(event.data.object) do
    {:ok, _} -> :ok
    {:error, :temporary_failure} -> {:error, "Database unavailable, retry later"}
    {:error, _reason} -> :ok  # Don't retry for permanent failures
  end
end
```

### Async Processing

For long-running operations, enqueue a job:

```elixir
handle "customer.subscription.deleted", fn event ->
  # Quick acknowledgment, process async
  MyApp.Jobs.queue_subscription_cancellation(event.data.object.id)
  :ok
end
```

## Event Types

Common Stripe events:
- `customer.created`, `customer.updated`, `customer.deleted`
- `payment_intent.succeeded`, `payment_intent.payment_failed`
- `invoice.paid`, `invoice.payment_failed`
- `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`
- `charge.succeeded`, `charge.failed`, `charge.refunded`

View all supported events:
```bash
cat deps/tiny_elixir_stripe/priv/supported_stripe_events.txt
```

## Testing

### Testing Webhooks Locally

Use the Stripe CLI to forward webhooks:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

Trigger test events:

```bash
stripe trigger customer.created
stripe trigger payment_intent.succeeded
```

### Testing in Code

Create test events manually:

```elixir
test "handles customer.created event" do
  event = %{
    id: "evt_test",
    type: "customer.created",
    data: %{
      object: %{
        id: "cus_test",
        email: "test@example.com"
      }
    }
  }
  
  assert :ok = MyApp.StripeWebhookHandlers.handle_event(event)
end
```

## Mix Tasks

- `mix tiny_elixir_stripe.install` - Install and configure TinyElixirStripe
- `mix tiny_elixir_stripe.gen.handler <event>` - Generate a handler for a specific event
- `mix tiny_elixir_stripe.set_webhook_path <path>` - Update the webhook route path
- `mix tiny_elixir_stripe.sync_webhook_handlers` - Sync handlers with Stripe (if using Spark introspection)

## Common Mistakes

- **Don't hardcode API keys**: Always use environment variables
- **Don't skip signature verification**: The installer configures this automatically
- **Don't block webhook handlers**: Keep handlers fast, enqueue long operations
- **Don't forget to return `:ok`**: Handlers must return `:ok` or `{:error, reason}`
- **Don't process webhooks twice**: Make handlers idempotent
- **Don't use in production without testing**: Test with Stripe CLI first

## Best Practices

1. **Keep handlers simple**: Complex logic should be in separate modules
2. **Log webhook processing**: Helpful for debugging
3. **Monitor webhook failures**: Set up alerts for repeated failures
4. **Version your API**: Stripe has multiple API versions, be consistent
5. **Handle all expected events**: Unhandled events are logged but don't cause errors
6. **Test with Stripe CLI**: Always test webhooks before deploying

## Troubleshooting

**Webhook signature verification fails**:
- Check that `ParsersWithRawBody` is configured in your endpoint
- Verify `STRIPE_WEBHOOK_SECRET` environment variable is set correctly
- Ensure you're using the secret from the Stripe webhook endpoint settings

**Events not being handled**:
- Check handler module is referenced in the WebhookController
- Verify handler is defined for that specific event type
- Check application logs for errors

**API requests failing**:
- Verify `STRIPE_SECRET_KEY` environment variable is set
- Check API key has correct permissions
- Ensure you're using the correct API version
