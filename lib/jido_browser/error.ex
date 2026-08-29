defmodule Jido.Browser.Error do
  @moduledoc """
  Explicit browser exception contracts and constructors.

  Browser APIs preserve the `{:error, exception}` return form. The exception
  modules in this namespace are the public failure categories. Constructors
  remove sensitive values from messages and details before an exception leaves
  the browser boundary.
  """

  @redacted "[REDACTED]"
  @sensitive_detail_keys ~w(
    authorization
    body
    cookie
    cookie2
    credential
    credentials
    headers
    passphrase
    password
    payload
    proxy_authorization
    response
    script
    secret
    text
    token
  )

  defmodule AdapterError do
    @moduledoc "An adapter or browser-runtime failure."

    @type t :: %__MODULE__{message: String.t(), adapter: module() | nil, details: map()}
    defexception message: "Browser adapter failed", adapter: nil, details: %{}

    @impl true
    def message(%{message: message, adapter: adapter}) do
      if adapter, do: "[#{adapter}] #{message}", else: message
    end
  end

  defmodule NavigationError do
    @moduledoc "A failure while navigating to a browser location."

    @type t :: %__MODULE__{message: String.t(), url: String.t() | nil, details: map()}
    defexception message: "Navigation failed", url: nil, details: %{}

    @impl true
    def message(%{message: message, url: url}) do
      if url, do: "Navigation to #{url} failed: #{message}", else: message
    end
  end

  defmodule ElementError do
    @moduledoc "A failure while finding or interacting with a page element."

    @type t :: %__MODULE__{
            message: String.t(),
            action: String.t() | nil,
            selector: String.t() | nil,
            details: map()
          }
    defexception message: "Element interaction failed", action: nil, selector: nil, details: %{}

    @impl true
    def message(%{message: message, action: action, selector: selector}) do
      "Failed to #{action} element '#{selector}': #{message}"
    end
  end

  defmodule TimeoutError do
    @moduledoc "A browser operation that exceeded its allowed duration."

    @type t :: %__MODULE__{
            message: String.t(),
            timeout_ms: non_neg_integer() | nil,
            operation: String.t() | nil,
            details: map()
          }
    defexception message: "Timeout", timeout_ms: nil, operation: nil, details: %{}

    @impl true
    def message(%{operation: operation, timeout_ms: timeout_ms}) do
      "Operation #{operation} timed out after #{timeout_ms}ms"
    end
  end

  defmodule EvaluationError do
    @moduledoc "A failure while evaluating browser JavaScript."

    @type t :: %__MODULE__{message: String.t(), script: String.t() | nil, details: map()}
    defexception message: "JavaScript evaluation failed", script: nil, details: %{}

    @impl true
    def message(%{message: message, script: script}) do
      if script, do: "JavaScript evaluation failed: #{message}", else: message
    end
  end

  defmodule InvalidError do
    @moduledoc "An invalid browser option, input, state, or policy decision."

    @type t :: %__MODULE__{message: String.t(), details: map()}
    defexception message: "Invalid browser input", details: %{}

    @impl true
    def message(%{message: message}), do: message
  end

  defmodule InternalError do
    @moduledoc "An unexpected internal browser failure."

    @type t :: %__MODULE__{message: String.t(), details: map()}
    defexception message: "Internal browser error", details: %{}

    @impl true
    def message(%{message: message}), do: message
  end

  @typedoc "A public Jido Browser exception."
  @type t ::
          AdapterError.t()
          | NavigationError.t()
          | ElementError.t()
          | TimeoutError.t()
          | EvaluationError.t()
          | InvalidError.t()
          | InternalError.t()

  @doc "Creates an adapter error with the given message and optional details."
  @spec adapter_error(String.t(), map()) :: AdapterError.t()
  def adapter_error(message, details \\ %{}) do
    AdapterError.exception(
      message: sanitize_text(message),
      adapter: Map.get(details, :adapter),
      details: sanitize_details(details)
    )
  end

  @doc "Creates a navigation error for the given URL and reason."
  @spec navigation_error(String.t() | nil, term()) :: NavigationError.t()
  def navigation_error(url, reason) do
    NavigationError.exception(
      message: reason_message(reason),
      url: sanitize_url(url),
      details: sanitize_details(%{reason: reason})
    )
  end

  @doc "Creates an element error for the given action, selector, and reason."
  @spec element_error(String.t(), String.t(), term()) :: ElementError.t()
  def element_error(action, selector, reason) do
    ElementError.exception(
      message: reason_message(reason),
      action: sanitize_text(action),
      selector: sanitize_selector(selector),
      details: sanitize_details(%{reason: reason})
    )
  end

  @doc "Creates a timeout error for the given operation and timeout duration."
  @spec timeout_error(String.t(), non_neg_integer()) :: TimeoutError.t()
  def timeout_error(operation, timeout_ms) do
    TimeoutError.exception(
      operation: sanitize_text(operation),
      timeout_ms: timeout_ms,
      details: %{}
    )
  end

  @doc "Creates a JavaScript evaluation error without retaining the script."
  @spec evaluation_error(String.t(), map()) :: EvaluationError.t()
  def evaluation_error(message, details \\ %{}) do
    EvaluationError.exception(
      message: sanitize_text(message),
      script: nil,
      details: sanitize_details(details)
    )
  end

  @doc "Creates an invalid input, state, or policy error."
  @spec invalid_error(String.t(), map()) :: InvalidError.t()
  def invalid_error(message, details \\ %{}) do
    InvalidError.exception(message: sanitize_text(message), details: sanitize_details(details))
  end

  @doc "Creates an unexpected internal browser error."
  @spec internal_error(String.t(), map()) :: InternalError.t()
  def internal_error(message \\ "Internal browser error", details \\ %{}) do
    InternalError.exception(message: sanitize_text(message), details: sanitize_details(details))
  end

  defp sanitize_details(details) do
    Map.new(details, fn {key, value} -> {key, sanitize_detail(key, value)} end)
  end

  defp sanitize_detail(key, value) do
    name = key |> to_string() |> String.downcase() |> String.replace("-", "_")

    cond do
      sensitive_detail_key?(name) -> @redacted
      name == "url" or String.ends_with?(name, "_url") -> sanitize_url(value)
      name == "selector" -> sanitize_selector(value)
      true -> sanitize_value(value)
    end
  end

  defp sensitive_detail_key?(name) do
    name in @sensitive_detail_keys or
      String.ends_with?(name, "_password") or
      String.ends_with?(name, "_secret") or
      String.ends_with?(name, "_token") or
      String.ends_with?(name, "_api_key")
  end

  defp sanitize_value(%_module{} = value), do: value

  defp sanitize_value(value) when is_map(value) do
    sanitize_details(value)
  end

  defp sanitize_value(value) when is_list(value), do: Enum.map(value, &sanitize_value/1)

  defp sanitize_value(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&sanitize_value/1)
    |> List.to_tuple()
  end

  defp sanitize_value(value) when is_binary(value), do: sanitize_text(value)
  defp sanitize_value(value), do: value

  defp sanitize_selector(selector) when is_binary(selector) do
    if Regex.match?(~r/(authorization|cookie|password|secret|token)/i, selector) do
      @redacted
    else
      sanitize_text(selector)
    end
  end

  defp sanitize_selector(selector), do: selector

  defp sanitize_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = uri when is_binary(scheme) and is_binary(host) ->
        %{uri | userinfo: nil, query: redact_query(uri.query), fragment: nil}
        |> URI.to_string()

      _uri ->
        sanitize_text(url)
    end
  end

  defp sanitize_url(url), do: url

  defp redact_query(nil), do: nil
  defp redact_query(_query), do: @redacted

  defp reason_message(reason) when is_exception(reason), do: reason |> Exception.message() |> sanitize_text()
  defp reason_message(reason), do: reason |> inspect() |> sanitize_text()

  defp sanitize_text(text) when is_binary(text) do
    text
    |> then(&Regex.replace(~r/\bbearer\s+[^\s,;]+/i, &1, "Bearer #{@redacted}"))
    |> then(
      &Regex.replace(
        ~r/\b(authorization|cookie|password|passphrase|secret|token|api[_-]?key)\b\s*[:=]\s*[^\s,;]+/i,
        &1,
        "\\1=#{@redacted}"
      )
    )
  end
end
