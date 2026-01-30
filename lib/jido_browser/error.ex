defmodule JidoBrowser.Error do
  @moduledoc """
  Centralized error handling for JidoBrowser using Splode.

  Error classes are for classification; concrete `...Error` structs are for raising/matching.
  """

  use Splode,
    error_classes: [
      invalid: Invalid,
      adapter: Adapter,
      navigation: Navigation,
      element: Element,
      timeout: Timeout
    ],
    unknown_error: __MODULE__.Unknown.UnknownError

  # Error classes – classification only

  defmodule Invalid do
    @moduledoc "Invalid input error class."
    use Splode.ErrorClass, class: :invalid
  end

  defmodule Adapter do
    @moduledoc "Adapter-level error class."
    use Splode.ErrorClass, class: :adapter
  end

  defmodule Navigation do
    @moduledoc "Navigation error class."
    use Splode.ErrorClass, class: :navigation
  end

  defmodule Element do
    @moduledoc "Element interaction error class."
    use Splode.ErrorClass, class: :element
  end

  defmodule Timeout do
    @moduledoc "Timeout error class."
    use Splode.ErrorClass, class: :timeout
  end

  defmodule Unknown do
    @moduledoc "Unknown error class."
    use Splode.ErrorClass, class: :unknown

    defmodule UnknownError do
      @moduledoc false
      defexception [:message, :details]

      @impl true
      def message(%{message: message}), do: message
    end
  end

  # Concrete exception structs

  defmodule AdapterError do
    @moduledoc "Error from the browser adapter."
    @type t :: %__MODULE__{message: String.t(), adapter: module() | nil, details: map() | nil}
    defexception [:message, :adapter, :details]

    @impl true
    def message(%{message: message, adapter: adapter}) do
      if adapter, do: "[#{adapter}] #{message}", else: message
    end
  end

  defmodule NavigationError do
    @moduledoc "Error navigating to a URL."
    @type t :: %__MODULE__{message: String.t(), url: String.t() | nil, details: map() | nil}
    defexception [:message, :url, :details]

    @impl true
    def message(%{message: message, url: url}) do
      if url, do: "Navigation to #{url} failed: #{message}", else: message
    end
  end

  defmodule ElementError do
    @moduledoc "Error interacting with an element."
    @type t :: %__MODULE__{
            message: String.t(),
            action: String.t() | nil,
            selector: String.t() | nil,
            details: map() | nil
          }
    defexception [:message, :action, :selector, :details]

    @impl true
    def message(%{message: message, action: action, selector: selector}) do
      "Failed to #{action} element '#{selector}': #{message}"
    end
  end

  defmodule TimeoutError do
    @moduledoc "Operation timed out."
    @type t :: %__MODULE__{
            message: String.t(),
            timeout_ms: non_neg_integer() | nil,
            operation: String.t() | nil,
            details: map() | nil
          }
    defexception [:message, :timeout_ms, :operation, :details]

    @impl true
    def message(%{operation: operation, timeout_ms: timeout_ms}) do
      "Operation #{operation} timed out after #{timeout_ms}ms"
    end
  end

  defmodule EvaluationError do
    @moduledoc "Error evaluating JavaScript."
    defexception [:message, :script, :details]

    @impl true
    def message(%{message: message, script: script}) do
      if script, do: "JavaScript evaluation failed: #{message}", else: message
    end
  end

  defmodule InvalidError do
    @moduledoc "Invalid input or state error."
    @type t :: %__MODULE__{message: String.t(), details: map() | nil}
    defexception [:message, :details]

    @impl true
    def message(%{message: message}), do: message
  end

  # Helper functions

  @doc "Creates an adapter error with the given message and optional details."
  @spec adapter_error(String.t(), map()) :: AdapterError.t()
  def adapter_error(message, details \\ %{}) do
    AdapterError.exception(
      message: message,
      adapter: details[:adapter],
      details: details
    )
  end

  @doc "Creates a navigation error for the given URL and reason."
  @spec navigation_error(String.t() | nil, term()) :: NavigationError.t()
  def navigation_error(url, reason) do
    NavigationError.exception(
      message: inspect(reason),
      url: url,
      details: %{reason: reason}
    )
  end

  @doc "Creates an element error for the given action, selector, and reason."
  @spec element_error(String.t(), String.t(), term()) :: ElementError.t()
  def element_error(action, selector, reason) do
    ElementError.exception(
      message: inspect(reason),
      action: action,
      selector: selector,
      details: %{reason: reason}
    )
  end

  @doc "Creates a timeout error for the given operation and timeout duration."
  @spec timeout_error(String.t(), non_neg_integer()) :: TimeoutError.t()
  def timeout_error(operation, timeout_ms) do
    TimeoutError.exception(
      message: "Timeout",
      operation: operation,
      timeout_ms: timeout_ms,
      details: %{}
    )
  end

  @doc "Creates an invalid input/state error with the given message and optional details."
  @spec invalid_error(String.t(), map()) :: InvalidError.t()
  def invalid_error(message, details \\ %{}) do
    InvalidError.exception(message: message, details: details)
  end
end
