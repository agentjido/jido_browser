defmodule Jido.Browser.WebFetch.Content do
  @moduledoc false

  alias Jido.Browser.Error
  alias Jido.Browser.WebFetch.DocumentExtractor

  @html_content_types ["text/html", "application/xhtml+xml"]
  @text_content_types [
    "text/plain",
    "text/markdown",
    "text/csv",
    "text/xml",
    "application/xml",
    "application/json",
    "application/ld+json"
  ]
  @document_content_types %{
    "application/pdf" => :pdf,
    "application/msword" => :word_processing,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => :word_processing,
    "application/vnd.ms-word.document.macroenabled.12" => :word_processing,
    "application/vnd.openxmlformats-officedocument.wordprocessingml.template" => :word_processing,
    "application/vnd.ms-word.template.macroenabled.12" => :word_processing,
    "application/vnd.ms-excel" => :spreadsheet,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => :spreadsheet,
    "application/vnd.ms-excel.sheet.macroenabled.12" => :spreadsheet,
    "application/vnd.openxmlformats-officedocument.spreadsheetml.template" => :spreadsheet,
    "application/vnd.ms-excel.template.macroenabled.12" => :spreadsheet,
    "application/vnd.ms-powerpoint" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => :presentation,
    "application/vnd.ms-powerpoint.presentation.macroenabled.12" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.slideshow" => :presentation,
    "application/vnd.openxmlformats-officedocument.presentationml.template" => :presentation,
    "application/vnd.oasis.opendocument.text" => :word_processing,
    "application/vnd.oasis.opendocument.spreadsheet" => :spreadsheet,
    "application/vnd.oasis.opendocument.presentation" => :presentation,
    "application/rtf" => :word_processing,
    "text/rtf" => :word_processing,
    "application/epub+zip" => :ebook,
    "message/rfc822" => :email,
    "application/vnd.ms-outlook" => :email
  }
  @document_extensions %{
    "pdf" => :pdf,
    "doc" => :word_processing,
    "docx" => :word_processing,
    "docm" => :word_processing,
    "dotx" => :word_processing,
    "dotm" => :word_processing,
    "odt" => :word_processing,
    "rtf" => :word_processing,
    "xls" => :spreadsheet,
    "xlsx" => :spreadsheet,
    "xlsm" => :spreadsheet,
    "xlsb" => :spreadsheet,
    "ods" => :spreadsheet,
    "ppt" => :presentation,
    "pptx" => :presentation,
    "pptm" => :presentation,
    "ppsx" => :presentation,
    "odp" => :presentation,
    "epub" => :ebook,
    "eml" => :email,
    "msg" => :email
  }

  @doc false
  @spec extract(String.t(), map(), keyword()) :: {:ok, map()} | {:error, Exception.t()}
  def extract(final_url, response, opts) do
    content_type = response_content_type(response)
    document_type = extractable_document_type(content_type, final_url, response.body)

    cond do
      content_type in @html_content_types ->
        extract_html(response.body, content_type, opts)

      not is_nil(document_type) ->
        extract_document(response.body, final_url, content_type, document_type, opts)

      text_content_type?(content_type) ->
        extract_text(response.body, content_type, opts)

      true ->
        {:error,
         Error.adapter_error("Unsupported content type for web fetch", %{
           error_code: :unsupported_content_type,
           content_type: content_type
         })}
    end
  end

  @doc false
  @spec response_header(map(), String.t()) :: list()
  def response_header(headers, name) when is_map(headers) do
    headers
    |> Map.get(name, Map.get(headers, String.downcase(name), []))
    |> List.wrap()
  end

  defp extract_html(body, content_type, opts) when is_binary(body) do
    selector = opts[:selector]

    with {:ok, document} <- parse_document(body),
         {:ok, html} <- select_html(document, body, selector),
         {:ok, title} <- extract_title(document),
         {:ok, content} <- format_html(html, opts[:format], opts) do
      {:ok,
       %{
         content: content,
         title: title,
         content_type: content_type,
         document_type: :html,
         metadata: nil
       }}
    end
  end

  defp extract_html(body, content_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for HTML fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp extract_text(body, content_type, opts) when is_binary(body) do
    with :ok <- validate_non_html_options(content_type, opts),
         {:ok, content} <- format_text(body, opts[:format]) do
      {:ok,
       %{
         content: content,
         title: nil,
         content_type: content_type,
         document_type: :text,
         metadata: nil
       }}
    end
  end

  defp extract_text(body, content_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for text fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp extract_document(body, final_url, content_type, document_type, opts) when is_binary(body) do
    with :ok <- validate_non_html_options(content_type, opts),
         {:ok, text, metadata} <- extract_document_content(body, final_url, content_type, document_type, opts) do
      {:ok,
       %{
         content: text,
         title: document_title(metadata, final_url),
         content_type: content_type,
         document_type: document_type,
         metadata: metadata
       }}
    end
  end

  defp extract_document(body, _final_url, content_type, _document_type, _opts) do
    {:error,
     Error.adapter_error("Unexpected response body for document fetch", %{
       error_code: :unavailable,
       content_type: content_type,
       body: body
     })}
  end

  defp validate_non_html_options(content_type, opts) do
    cond do
      opts[:selector] ->
        {:error,
         Error.invalid_error("Selector filtering is only supported for HTML content", %{
           error_code: :invalid_input,
           selector: opts[:selector],
           content_type: content_type
         })}

      opts[:format] == :html ->
        {:error,
         Error.invalid_error("HTML output is only supported for HTML content", %{
           error_code: :invalid_input,
           format: :html,
           content_type: content_type
         })}

      true ->
        :ok
    end
  end

  defp parse_document(body) do
    case Floki.parse_document(body) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} ->
        {:error, Error.adapter_error("Failed to parse fetched HTML", %{error_code: :unavailable, reason: reason})}
    end
  end

  defp select_html(_document, body, nil), do: {:ok, body}
  defp select_html(document, _body, ""), do: select_html(document, nil, nil)

  defp select_html(document, _body, selector) do
    nodes = Floki.find(document, selector)

    if nodes == [] do
      {:error,
       Error.invalid_error("Selector did not match any elements in fetched HTML", %{
         error_code: :invalid_input,
         selector: selector
       })}
    else
      {:ok, Floki.raw_html(nodes)}
    end
  end

  defp extract_title(document) do
    title =
      document
      |> Floki.find("title")
      |> Floki.text(sep: " ")
      |> String.trim()
      |> blank_to_nil()

    {:ok, title}
  end

  defp format_html(html, :html, _opts), do: {:ok, html}

  defp format_html(html, :text, _opts) do
    with {:ok, fragment} <- parse_fragment(html) do
      {:ok, fragment |> Floki.text(sep: "\n") |> String.trim()}
    end
  end

  defp format_html(html, :markdown, _opts) do
    {:ok, Html2Markdown.convert(html) |> String.trim()}
  rescue
    error ->
      {:error,
       Error.adapter_error("Failed to convert fetched HTML to markdown", %{error_code: :unavailable, reason: error})}
  end

  defp format_text(text, :text), do: {:ok, String.trim(text)}
  defp format_text(text, :markdown), do: {:ok, String.trim(text)}

  defp format_text(_text, :html) do
    {:error,
     Error.invalid_error("HTML output is only supported for HTML content", %{
       error_code: :invalid_input
     })}
  end

  defp parse_fragment(html) do
    case Floki.parse_fragment(html) do
      {:ok, fragment} ->
        {:ok, fragment}

      {:error, reason} ->
        {:error,
         Error.adapter_error("Failed to parse fetched HTML fragment", %{error_code: :unavailable, reason: reason})}
    end
  end

  defp extract_document_content(bytes, final_url, content_type, document_type, opts) do
    case DocumentExtractor.extract(bytes, opts[:extractous]) do
      {:ok, %{content: content, metadata: metadata}} when is_binary(content) ->
        {:ok, String.trim(content), normalize_metadata(metadata)}

      {:error, reason} ->
        {:error,
         Error.adapter_error("ExtractousEx failed while extracting document content", %{
           error_code: :unavailable,
           url: final_url,
           content_type: content_type,
           document_type: document_type,
           reason: reason
         })}
    end
  rescue
    error ->
      {:error,
       Error.adapter_error("ExtractousEx failed while extracting document content", %{
         error_code: :unavailable,
         url: final_url,
         content_type: content_type,
         document_type: document_type,
         reason: error
       })}
  end

  defp response_content_type(response) do
    response.headers
    |> response_header("content-type")
    |> List.first()
    |> case do
      nil -> infer_content_type(response.body)
      content_type -> content_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()
    end
  end

  defp infer_content_type(body) when is_binary(body) do
    cond do
      String.starts_with?(body, "%PDF-") ->
        "application/pdf"

      likely_text?(body) ->
        "text/plain"

      true ->
        "application/octet-stream"
    end
  end

  defp infer_content_type(_body), do: "application/octet-stream"

  defp text_content_type?(content_type) do
    content_type in @text_content_types or String.starts_with?(content_type, "text/")
  end

  defp extractable_document_type(content_type, final_url, body) do
    Map.get(@document_content_types, content_type) ||
      infer_document_type_from_body(body) ||
      if(ambiguous_binary_content_type?(content_type), do: infer_document_type_from_url(final_url), else: nil)
  end

  defp infer_document_type_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path, "")
    |> Path.extname()
    |> String.trim_leading(".")
    |> String.downcase()
    |> case do
      "" -> nil
      extension -> Map.get(@document_extensions, extension)
    end
  end

  defp infer_document_type_from_body(body) when is_binary(body) do
    if String.starts_with?(body, "%PDF-"), do: :pdf, else: nil
  end

  defp infer_document_type_from_body(_body), do: nil

  defp document_title(metadata, url) do
    metadata
    |> metadata_title()
    |> blank_to_nil()
    |> case do
      nil -> title_from_url(url)
      title -> title
    end
  end

  defp metadata_title(metadata) when is_map(metadata) do
    Enum.find_value([:title, "title", "dc:title", :"dc:title"], fn key ->
      metadata
      |> Map.get(key)
      |> metadata_value_to_string()
      |> blank_to_nil()
    end)
  end

  defp metadata_value_to_string(nil), do: nil
  defp metadata_value_to_string(value) when is_binary(value), do: String.trim(value)

  defp metadata_value_to_string(value) when is_list(value),
    do: value |> Enum.map_join(" ", &to_string/1) |> String.trim()

  defp metadata_value_to_string(value) when is_atom(value), do: value |> Atom.to_string() |> String.trim()
  defp metadata_value_to_string(value) when is_number(value), do: value |> to_string() |> String.trim()
  defp metadata_value_to_string(_value), do: nil

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata

  defp title_from_url(url) do
    path = URI.parse(url).path || ""

    case path do
      "" -> nil
      "/" -> nil
      value -> value |> Path.basename() |> String.trim("/") |> blank_to_nil()
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp ambiguous_binary_content_type?(content_type) do
    content_type in [
      "application/octet-stream",
      "binary/octet-stream",
      "application/download",
      "application/x-download",
      "application/zip",
      "application/x-zip-compressed"
    ]
  end

  defp likely_text?(body) when is_binary(body) do
    String.valid?(body) and not String.contains?(body, <<0>>)
  end
end
