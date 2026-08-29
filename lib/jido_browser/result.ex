defmodule Jido.Browser.Result do
  @moduledoc """
  Shared contracts for successful browser operation results.

  Public result maps use atom keys. Adapter protocol fields are normalized at
  the adapter boundary. Dynamic identifiers, such as keys in a `:refs` map,
  stay as strings because they are values, not public field names.

  The values under `:result`, `:metadata`, and `:raw` are opaque. They can keep
  the key style supplied by JavaScript, an extractor, or an upstream runtime.
  Unknown upstream fields are placed under `:raw` instead of becoming atoms at
  runtime.
  """

  @typedoc "A normalized successful operation result."
  @type t :: %{optional(atom()) => term()}

  @typedoc "A result that identifies a page or navigation target."
  @type navigation :: %{
          optional(:url) => String.t() | nil,
          optional(:title) => String.t() | nil,
          optional(:elapsed) => non_neg_integer(),
          optional(:raw) => map()
        }

  @typedoc "A result for an element interaction."
  @type interaction :: %{
          optional(:selector) => String.t(),
          optional(:value) => term(),
          optional(:error) => term(),
          optional(:raw) => map()
        }

  @typedoc "A browser screenshot result."
  @type screenshot :: %{
          required(:bytes) => binary(),
          required(:mime) => String.t(),
          optional(:format) => atom()
        }

  @typedoc "An extracted page or document result."
  @type content :: %{
          required(:content) => String.t(),
          required(:format) => atom(),
          optional(:metadata) => map()
        }

  @typedoc "A JavaScript evaluation result. The value is intentionally opaque."
  @type evaluation :: %{required(:result) => term()}

  @typedoc "A normalized browser tab entry."
  @type tab :: %{
          optional(:index) => non_neg_integer(),
          optional(:tab_id) => String.t(),
          optional(:url) => String.t() | nil,
          optional(:title) => String.t() | nil,
          optional(:active) => boolean(),
          optional(:raw) => map()
        }

  @field_names %{
    "action" => :action,
    "active" => :active,
    "adapter" => :adapter,
    "age" => :age,
    "alive" => :alive,
    "attribute" => :attribute,
    "blocked" => :blocked,
    "blocked?" => :blocked?,
    "cached" => :cached,
    "citations" => :citations,
    "classes" => :classes,
    "content" => :content,
    "contentType" => :content_type,
    "content_type" => :content_type,
    "count" => :count,
    "cursor" => :cursor,
    "description" => :description,
    "direction" => :direction,
    "documentType" => :document_type,
    "document_type" => :document_type,
    "elapsed" => :elapsed,
    "elapsedMs" => :elapsed_ms,
    "elapsed_ms" => :elapsed_ms,
    "error" => :error,
    "errors" => :errors,
    "estimatedTokens" => :estimated_tokens,
    "estimated_tokens" => :estimated_tokens,
    "exists" => :exists,
    "fallback" => :fallback,
    "fallbackReason" => :fallback_reason,
    "fallback_reason" => :fallback_reason,
    "filtered" => :filtered,
    "finalUrl" => :final_url,
    "final_url" => :final_url,
    "focusMatches" => :focus_matches,
    "focus_matches" => :focus_matches,
    "focused" => :focused,
    "format" => :format,
    "forms" => :forms,
    "found" => :found,
    "headings" => :headings,
    "height" => :height,
    "hovered" => :hovered,
    "href" => :href,
    "html" => :html,
    "id" => :id,
    "index" => :index,
    "items" => :items,
    "label" => :label,
    "level" => :level,
    "links" => :links,
    "message" => :message,
    "messages" => :messages,
    "metadata" => :metadata,
    "mime" => :mime,
    "name" => :name,
    "origin" => :origin,
    "originalEstimatedTokens" => :original_estimated_tokens,
    "original_estimated_tokens" => :original_estimated_tokens,
    "passages" => :passages,
    "path" => :path,
    "pages" => :pages,
    "query" => :query,
    "raw" => :raw,
    "refs" => :refs,
    "result" => :result,
    "results" => :results,
    "retrievalPath" => :retrieval_path,
    "retrieval_path" => :retrieval_path,
    "retrievedAt" => :retrieved_at,
    "retrieved_at" => :retrieved_at,
    "role" => :role,
    "scrolled" => :scrolled,
    "selected" => :selected,
    "selector" => :selector,
    "snapshot" => :snapshot,
    "snippet" => :snippet,
    "startChar" => :start_char,
    "start_char" => :start_char,
    "endChar" => :end_char,
    "end_char" => :end_char,
    "status" => :status,
    "tabId" => :tab_id,
    "tab_id" => :tab_id,
    "tabs" => :tabs,
    "tag" => :tag,
    "text" => :text,
    "texts" => :texts,
    "title" => :title,
    "truncated" => :truncated,
    "type" => :type,
    "url" => :url,
    "value" => :value,
    "values" => :values,
    "visible" => :visible,
    "width" => :width,
    "x" => :x,
    "y" => :y
  }

  @opaque_fields [:metadata, :raw, :result]

  @doc """
  Normalizes a successful result map to the public atom-key contract.

  This function never creates atoms from runtime input.
  """
  @spec normalize(map()) :: t()
  def normalize(result) when is_map(result) do
    Enum.reduce(result, %{}, fn
      {key, value}, normalized when is_atom(key) ->
        Map.put(normalized, key, normalize_value(key, value))

      {key, value}, normalized when is_binary(key) ->
        case @field_names do
          %{^key => public_key} -> Map.put(normalized, public_key, normalize_value(public_key, value))
          _other -> put_raw(normalized, key, value)
        end

      {key, value}, normalized ->
        put_raw(normalized, key, value)
    end)
  end

  defp normalize_value(key, value) when key in @opaque_fields, do: value

  defp normalize_value(:refs, refs) when is_map(refs) do
    Map.new(refs, fn {identifier, value} -> {identifier, normalize_nested(value)} end)
  end

  defp normalize_value(_key, value), do: normalize_nested(value)

  defp normalize_nested(value) when is_map(value), do: normalize(value)
  defp normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  defp normalize_nested(value), do: value

  defp put_raw(normalized, key, value) do
    Map.update(normalized, :raw, %{key => value}, &Map.put(&1, key, value))
  end
end
