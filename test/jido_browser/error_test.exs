defmodule JidoBrowser.ErrorTest do
  use ExUnit.Case, async: true

  alias JidoBrowser.Error

  describe "adapter_error/2" do
    test "creates AdapterError" do
      error = Error.adapter_error("Connection failed", %{reason: :timeout})

      assert %Error.AdapterError{} = error
      assert error.message == "Connection failed"
      assert error.details == %{reason: :timeout}
    end
  end

  describe "navigation_error/2" do
    test "creates NavigationError" do
      error = Error.navigation_error("https://example.com", :timeout)

      assert %Error.NavigationError{} = error
      assert error.url == "https://example.com"
      assert Exception.message(error) =~ "Navigation to https://example.com failed"
    end
  end

  describe "element_error/3" do
    test "creates ElementError" do
      error = Error.element_error("click", "button#submit", :not_found)

      assert %Error.ElementError{} = error
      assert error.action == "click"
      assert error.selector == "button#submit"
      assert Exception.message(error) =~ "Failed to click element 'button#submit'"
    end
  end

  describe "timeout_error/2" do
    test "creates TimeoutError" do
      error = Error.timeout_error("navigate", 30_000)

      assert %Error.TimeoutError{} = error
      assert error.operation == "navigate"
      assert error.timeout_ms == 30_000
      assert Exception.message(error) =~ "timed out after 30000ms"
    end
  end
end
