defmodule PinStripe.WebhookHandler.Info do
  @moduledoc """
  Introspection functions for webhook handler DSL.
  """

  use Spark.InfoGenerator,
    extension: PinStripe.WebhookHandler.Dsl,
    sections: [:handlers]
end
