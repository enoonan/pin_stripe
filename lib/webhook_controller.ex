defmodule PinStripe.WebhookController do
  @moduledoc """
  Base controller for handling Stripe webhook events.

  This module provides a `use` macro that injects webhook handling functionality
  into your Phoenix controller. It automatically verifies webhook signatures and
  dispatches events to handler functions defined using the `handle/2` macro.

  ## Usage

  Create a controller in your Phoenix app and define event handlers:

      defmodule MyAppWeb.StripeWebhookController do
        use PinStripe.WebhookController

        handle "customer.created", fn event ->
          # Process customer.created event
          customer = event["data"]["object"]
          IO.inspect(customer, label: "New customer")
          :ok
        end

        handle "invoice.paid", MyApp.InvoicePaidHandler
      end

  Then add it to your router:

      scope "/webhooks" do
        pipe_through [:api]

        post "/stripe", StripeWebhookController, :create
      end

  ## Configuration

  Configure your webhook secret:

      config :pin_stripe,
        stripe_webhook_secret: "whsec_..."

  ## Security

  This controller automatically verifies webhook signatures using the
  `stripe-signature` header. Invalid signatures are rejected with a 400 response.

  The raw request body must be available in `conn.assigns.raw_body` for signature
  verification to work. Use PinStripe.ParsersWithRawBody in your endpoint.

  ## Handler Functions

  Handlers can be either:
  - Anonymous functions that take the event as an argument
  - Module names that implement a `handle_event/1` function

  ### Function Handler Example

      handle "customer.created", fn event ->
        # Process customer.created event
        :ok
      end

  ### Module Handler Example

      handle "invoice.paid", MyApp.InvoicePaidHandler

  Then create the handler module:

      defmodule MyApp.InvoicePaidHandler do
        def handle_event(event) do
          invoice = event["data"]["object"]
          # Process the paid invoice
          :ok
        end
      end

  ## Error Handling

  The controller returns HTTP 200 for any handler that completes normally (regardless
  of return value). Stripe considers a 200 response as successful delivery and will not
  retry the event.

  If a handler raises an exception, it propagates through Phoenix, which returns a 500
  response. Stripe treats any non-2xx response as a failure and retries with exponential
  backoff (5 min, 30 min, 2 hours, 5 hours, 10 hours, then every 12 hours).

  **Warning:** After 3 days of consecutive failures, Stripe disables the endpoint
  entirely. Once disabled, *all* events stop being delivered — not just the ones that
  failed. Use `raise` only for transient failures (e.g., database timeouts) where a
  retry is likely to succeed.

  ### Examples

      # Successful handling — returns 200
      handle "invoice.paid", fn event ->
        MyApp.Billing.process_invoice(event["data"]["object"])
        :ok
      end

      # Permanent failure — returns 200, handle the error yourself
      handle "checkout.session.completed", fn event ->
        case MyApp.Billing.provision(event) do
          :ok -> :ok
          {:error, reason} -> MyApp.ErrorReporter.report(reason, event)
        end
      end

      # Transient failure — raises, returns 500, Stripe retries
      handle "customer.subscription.updated", fn event ->
        MyApp.Billing.sync_subscription!(event["data"]["object"])
      end
  """

  defmacro __using__(_opts) do
    quote do
      use PinStripe.WebhookHandler
      use Phoenix.Controller, formats: [:json]
      import Plug.Conn
      require Logger

      @doc """
      Handles incoming Stripe webhook events.

      Expects a JSON payload with at least a "type" field indicating the event type.
      """
      def create(conn, %{"type" => type} = params) do
        conn = verify_signature(conn)

        if conn.halted do
          conn
        else
          Logger.info("[#{inspect(__MODULE__)}] Received webhook: #{type}")

          # Forward to this module's handle_event function (generated via `use PinStripe.WebhookHandler` above)
          __MODULE__.handle_event(type, params)

          send_resp(conn, 200, "")
        end
      end

      def create(conn, _params) do
        Logger.warning("[#{inspect(__MODULE__)}] Received webhook without type field")
        send_resp(conn, 400, "missing event type")
      end

      defp verify_signature(conn) do
        secret = Application.fetch_env!(:pin_stripe, :stripe_webhook_secret)
        "whsec_" <> _ = secret

        with {:ok, signature} <- get_signature(conn),
             raw_body <- reconstruct_raw_body(conn),
             :ok <- PinStripe.WebhookSignature.verify(raw_body, signature, secret) do
          conn
        else
          {:error, error} ->
            Logger.error("[#{inspect(__MODULE__)}] Invalid signature: #{error}")

            conn
            |> send_resp(400, "invalid signature")
            |> halt()
        end
      end

      defp get_signature(conn) do
        case get_req_header(conn, "stripe-signature") do
          [signature] -> {:ok, signature}
          _ -> {:error, "no signature"}
        end
      end

      defp reconstruct_raw_body(conn) do
        # Chunks are prepended, so reverse before concatenating
        conn.assigns.raw_body
        |> Enum.reverse()
        |> IO.iodata_to_binary()
      end
    end
  end
end
