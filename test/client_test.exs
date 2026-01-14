defmodule PinStripe.ClientTest do
  # async: false required for doctests that use Req.Test with shared plug names
  use ExUnit.Case, async: false
  doctest PinStripe
  doctest PinStripe.Client
  doctest PinStripe.Test.Fixtures
  doctest PinStripe.Test.Mock

  alias PinStripe.Client
  alias PinStripe.Test.Mock

  setup do
    # Config is set globally in test_helper.exs, no need to set or clean up here
    :ok
  end

  describe "read/2" do
    test "fetches a customer by ID successfully" do
      Mock.stub_read("cus_123", %{"id" => "cus_123", "email" => "test@example.com"})

      result = Client.read("cus_123")

      assert {:ok, %{body: %{"id" => "cus_123"}}} = result
    end

    test "handles customer not found" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      result = Client.read("cus_404")

      assert {:error, %{status: 404}} = result
    end

    test "fetches a product by deriving entity type from ID" do
      Mock.stub_read("product_123", %{"id" => "product_123", "name" => "Test Product"})

      result = Client.read("product_123")

      assert {:ok, %{body: %{"id" => "product_123"}}} = result
    end

    test "lists customers when given :customers atom" do
      customers = [
        %{"id" => "cus_1", "email" => "user1@example.com"},
        %{"id" => "cus_2", "email" => "user2@example.com"}
      ]

      Mock.stub_read(:customers, %{
        "object" => "list",
        "data" => customers,
        "has_more" => false
      })

      result = Client.read(:customers)

      assert {:ok, %{body: %{"object" => "list", "data" => data}}} = result
      assert length(data) == 2
    end

    test "lists products when given :products atom" do
      Mock.stub_read(:products, %{
        "object" => "list",
        "data" => [%{"id" => "product_1", "name" => "Product 1"}],
        "has_more" => false
      })

      result = Client.read(:products)

      assert {:ok, %{body: %{"object" => "list"}}} = result
    end

    test "returns error for unrecognized entity type" do
      result = Client.read(:invalid_entity)

      assert {:error, :unrecognized_entity_type} = result
    end

    test "lists with query parameters" do
      Mock.stub_read(:customers, %{
        "object" => "list",
        "data" => [],
        "has_more" => false
      })

      result = Client.read(:customers, limit: 10)

      assert {:ok, %{body: %{"object" => "list"}}} = result
    end
  end

  describe "create/3" do
    test "creates a customer successfully with params" do
      Mock.stub_create(:customers, %{"id" => "cus_new", "email" => "test@example.com"})

      result = Client.create(:customers, %{email: "test@example.com", name: "Test User"})

      assert {:ok, %{body: %{"id" => "cus_new"}}} = result
    end

    test "handles validation errors on create" do
      Mock.stub_error(:customers, 400, %{"error" => %{"message" => "Invalid email"}})

      result = Client.create(:customers, %{email: "invalid"})

      assert {:error, %{status: 400, body: %{"error" => %{"message" => "Invalid email"}}}} =
               result
    end

    test "creates a product with atom entity type" do
      Mock.stub_create(:products, %{"id" => "product_new", "name" => "Test Product"})

      result = Client.create(:products, %{name: "Test Product"})

      assert {:ok, %{body: %{"id" => "product_new"}}} = result
    end

    test "returns error for unrecognized entity type" do
      result = Client.create(:invalid_entity, %{foo: "bar"})

      assert {:error, :unrecognized_entity_type} = result
    end
  end

  describe "update/3" do
    test "updates a customer successfully with params" do
      Mock.stub_update("cus_123", %{"id" => "cus_123", "name" => "Updated Name"})

      result = Client.update("cus_123", %{name: "Updated Name"})

      assert {:ok, %{body: %{"id" => "cus_123", "name" => "Updated Name"}}} = result
    end

    test "handles update errors" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      result = Client.update("cus_404", %{name: "Test"})

      assert {:error, %{status: 404}} = result
    end
  end

  describe "delete/2" do
    test "deletes a customer successfully" do
      Mock.stub_delete("cus_123", %{"id" => "cus_123", "deleted" => true, "object" => "customer"})

      result = Client.delete("cus_123")

      assert {:ok, %{body: %{"deleted" => true}}} = result
    end

    test "handles delete errors" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      result = Client.delete("cus_404")

      assert {:error, %{status: 404}} = result
    end
  end

  describe "read!/2" do
    test "fetches a customer successfully and returns response" do
      Mock.stub_read("cus_123", %{"id" => "cus_123", "email" => "test@example.com"})

      response = Client.read!("cus_123")

      assert response.body["id"] == "cus_123"
    end

    test "raises on unrecognized entity type" do
      assert_raise RuntimeError, "Unrecognized entity type: :invalid", fn ->
        Client.read!(:invalid)
      end
    end

    test "raises on HTTP error" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.read!("cus_404")
      end
    end
  end

  describe "create!/3" do
    test "creates a customer successfully and returns response" do
      Mock.stub_create(:customers, %{"id" => "cus_new", "email" => "test@example.com"})

      response = Client.create!(:customers, %{email: "test@example.com"})

      assert response.body["id"] == "cus_new"
    end

    test "raises on unrecognized entity type" do
      assert_raise RuntimeError, "Unrecognized entity type: :invalid", fn ->
        Client.create!(:invalid, %{})
      end
    end

    test "raises on validation error" do
      Mock.stub_error(:customers, 400, %{"error" => %{"message" => "Invalid email"}})

      assert_raise RuntimeError, ~r/Request failed with status 400/, fn ->
        Client.create!(:customers, %{email: "invalid"})
      end
    end
  end

  describe "update!/3" do
    test "updates a customer successfully and returns response" do
      Mock.stub_update("cus_123", %{"id" => "cus_123", "name" => "Updated"})

      response = Client.update!("cus_123", %{name: "Updated"})

      assert response.body["name"] == "Updated"
    end

    test "raises on HTTP error" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.update!("cus_404", %{name: "Test"})
      end
    end
  end

  describe "delete!/2" do
    test "deletes a customer successfully and returns response" do
      Mock.stub_delete("cus_123", %{"id" => "cus_123", "deleted" => true, "object" => "customer"})

      response = Client.delete!("cus_123")

      assert response.body["deleted"] == true
    end

    test "raises on HTTP error" do
      Mock.stub_error("cus_404", 404, %{
        "error" => %{
          "type" => "invalid_request_error",
          "code" => "resource_missing",
          "message" => "No such resource"
        }
      })

      assert_raise RuntimeError, ~r/Request failed with status 404/, fn ->
        Client.delete!("cus_404")
      end
    end
  end

  describe "billing_portal_sessions" do
    test "creates a billing portal session" do
      Mock.stub_create(:billing_portal_sessions, %{
        "id" => "bps_123",
        "object" => "billing_portal.session",
        "url" => "https://billing.stripe.com/session/test_123"
      })

      result = Client.create(:billing_portal_sessions, %{customer: "cus_123"})

      assert {:ok, %{body: %{"id" => "bps_123", "object" => "billing_portal.session"}}} = result
    end

    test "reads a billing portal session by ID" do
      Mock.stub_read("bps_123", %{
        "id" => "bps_123",
        "object" => "billing_portal.session",
        "customer" => "cus_123"
      })

      result = Client.read("bps_123")

      assert {:ok, %{body: %{"id" => "bps_123"}}} = result
    end
  end
end
