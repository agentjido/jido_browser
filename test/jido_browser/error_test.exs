defmodule Jido.Browser.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Browser.Error

  @removed_class_modules [
    Error.Invalid,
    Error.Adapter,
    Error.Navigation,
    Error.Element,
    Error.Timeout,
    Error.Unknown,
    Error.Unknown.UnknownError
  ]

  @removed_splode_functions [
    {:from_json, 2},
    {:set_path, 2},
    {:splode_error?, 1},
    {:splode_error?, 2},
    {:to_class, 1},
    {:to_class, 2},
    {:to_error, 1},
    {:to_error, 2},
    {:traverse_errors, 2},
    {:unwrap!, 1},
    {:unwrap!, 2}
  ]

  test "creates an explicit adapter error" do
    error = Error.adapter_error("Connection failed", %{reason: :timeout})

    assert %Error.AdapterError{
             message: "Connection failed",
             adapter: nil,
             details: %{reason: :timeout}
           } = error

    assert Exception.message(error) == "Connection failed"
  end

  test "creates an explicit navigation error" do
    error = Error.navigation_error("https://example.com", :timeout)

    assert %Error.NavigationError{
             message: ":timeout",
             url: "https://example.com",
             details: %{reason: :timeout}
           } = error

    assert Exception.message(error) == "Navigation to https://example.com failed: :timeout"
  end

  test "creates an explicit element error" do
    error = Error.element_error("click", "button#submit", :not_found)

    assert %Error.ElementError{
             message: ":not_found",
             action: "click",
             selector: "button#submit",
             details: %{reason: :not_found}
           } = error

    assert Exception.message(error) == "Failed to click element 'button#submit': :not_found"
  end

  test "creates an explicit timeout error" do
    error = Error.timeout_error("navigate", 30_000)

    assert %Error.TimeoutError{
             message: "Timeout",
             operation: "navigate",
             timeout_ms: 30_000,
             details: %{}
           } = error

    assert Exception.message(error) == "Operation navigate timed out after 30000ms"
  end

  test "creates an evaluation error without keeping the script" do
    error = Error.evaluation_error("Evaluation failed", %{script: "window.secret"})

    assert %Error.EvaluationError{
             message: "Evaluation failed",
             script: nil,
             details: %{script: "[REDACTED]"}
           } = error

    assert Exception.message(error) == "Evaluation failed"
  end

  test "creates explicit invalid and internal errors" do
    assert %Error.InvalidError{message: "Invalid option", details: %{option: :timeout}} =
             Error.invalid_error("Invalid option", %{option: :timeout})

    assert %Error.InternalError{message: "Internal browser error", details: %{}} =
             Error.internal_error()
  end

  test "supports stable tagged error tuples for each public failure category" do
    errors = [
      Error.adapter_error("adapter"),
      Error.navigation_error("https://example.com", :navigation),
      Error.element_error("click", "button", :element),
      Error.timeout_error("wait", 100),
      Error.evaluation_error("evaluation"),
      Error.invalid_error("invalid"),
      Error.internal_error()
    ]

    assert Enum.all?(errors, fn error -> match?({:error, %_{}}, {:error, error}) end)
    assert Enum.all?(errors, &is_exception/1)
  end

  test "removes sensitive values from messages and details" do
    secret = "ultra-private-987"

    error =
      Error.adapter_error("Authorization: Bearer #{secret}", %{
        token: secret,
        payload: %{value: secret},
        nested: %{password: secret, reason: "token=#{secret}"},
        url: "https://user:#{secret}@example.com/path?token=#{secret}#private"
      })

    serialized = inspect(error) <> Exception.message(error)

    refute serialized =~ secret
    assert error.details.token == "[REDACTED]"
    assert error.details.payload == "[REDACTED]"
    assert error.details.nested.password == "[REDACTED]"
    refute error.details.url =~ "user:"
    refute error.details.url =~ "#private"
  end

  test "removes sensitive values from location and selector fields" do
    secret = "ultra-private-987"

    navigation =
      Error.navigation_error(
        "https://user:#{secret}@example.com/path?token=#{secret}#private",
        :failed
      )

    element =
      Error.element_error("type", "input[name=password][value=#{secret}]", :failed)

    evaluation = Error.evaluation_error("token=#{secret}", %{script: secret})

    refute inspect(navigation) <> Exception.message(navigation) =~ secret
    refute inspect(element) <> Exception.message(element) =~ secret
    refute inspect(evaluation) <> Exception.message(evaluation) =~ secret
    assert element.selector == "[REDACTED]"
    assert evaluation.script == nil
    assert evaluation.details.script == "[REDACTED]"
  end

  test "does not include the removed Splode classes in the application" do
    modules = Application.spec(:jido_browser, :modules)

    assert is_list(modules)
    refute Enum.any?(@removed_class_modules, &(&1 in modules))
  end

  test "does not export the removed Splode normalization functions" do
    refute Enum.any?(@removed_splode_functions, fn {name, arity} ->
             function_exported?(Error, name, arity)
           end)
  end
end
