defmodule PinStripe do
  @moduledoc """
  A minimal Stripe SDK for Elixir with webhook handling, built on Req and Spark.

  > #### Warning {: .warning}
  >
  > This library is still experimental! It's thoroughly tested in ExUnit, but that's it.

  PinStripe provides:

  - **Simple API Client** - Built on Req with automatic ID prefix recognition
  - **Webhook Handler DSL** - Using Spark for clean, declarative webhook handling
  - **Automatic Signature Verification** - For webhook security
  - **Code Generators** - Powered by Igniter for zero-config setup
  - **Sync with Stripe** - Keep your local handlers in sync with your Stripe dashboard

  ## Quick Start

  Install with Igniter:

      mix pin_stripe.install

  Configure your API key:

      config :pin_stripe,
        stripe_api_key: System.get_env("STRIPE_SECRET_KEY")

  Handle webhook events:

      defmodule MyApp.StripeWebhookHandlers do
        use PinStripe.WebhookHandler

        handle "customer.created", fn event ->
          # Your logic here
          :ok
        end
      end

  Call the Stripe API:

      alias PinStripe.Client

      {:ok, response} = Client.read("cus_123")
      {:ok, response} = Client.create(:customers, %{email: "test@example.com"})

  For full documentation, see the README.
  """
end
