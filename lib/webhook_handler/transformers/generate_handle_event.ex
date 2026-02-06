defmodule PinStripe.WebhookHandler.Transformers.GenerateHandleEvent do
  @moduledoc """
  Transformer that generates handle_event/2 functions and Phoenix controller code
  for webhook handlers.
  """

  use Spark.Dsl.Transformer

  def transform(dsl_state) do
    handlers = PinStripe.WebhookHandler.Info.handlers(dsl_state)

    # Generate only the handle_event/2 function
    code = generate_handle_event_functions(handlers)

    {:ok, Spark.Dsl.Transformer.eval(dsl_state, [], code)}
  end

  defp generate_handle_event_functions(handlers) do
    quote do
      @doc """
      Handles a webhook event by dispatching to the appropriate handler.

      The return value is ignored by the controller — any normal return results
      in an HTTP 200 response. To trigger a Stripe retry, raise an exception.
      See `PinStripe.WebhookController` for error handling details.

      Unknown event types return `:ok`.
      """
      def handle_event(event_type, event)

      unquote(generate_handler_clauses(handlers))

      # Catch-all clause for unknown event types
      def handle_event(_event_type, _event), do: :ok
    end
  end

  defp generate_handler_clauses(handlers) do
    Enum.map(handlers, fn handler ->
      quote do
        def handle_event(unquote(handler.event_type), event) do
          unquote(call_handler(handler))
        end
      end
    end)
  end

  defp call_handler(handler) do
    case handler.handler do
      fun when is_function(fun, 1) ->
        quote do
          unquote(Macro.escape(fun)).(event)
        end

      module when is_atom(module) ->
        quote do
          unquote(module).handle_event(event)
        end
    end
  end
end
