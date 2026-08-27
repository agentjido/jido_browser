defmodule Jido.Browser.WebFetch.Result do
  @moduledoc false

  @doc false
  @spec build(String.t(), String.t(), map(), keyword()) :: {:ok, map()}
  def build(url, final_url, content, opts) do
    with {:ok, filtered_content, filtered, focus_matches} <- maybe_filter_content(content.content, opts),
         {final_content, truncated, original_estimated_tokens} <-
           maybe_truncate(filtered_content, opts[:max_content_tokens]) do
      attrs = %{
        url: url,
        final_url: final_url,
        content: final_content,
        title: content.title,
        content_type: content.content_type,
        document_type: content.document_type,
        truncated: truncated,
        filtered: filtered,
        focus_matches: focus_matches,
        original_estimated_tokens: original_estimated_tokens,
        metadata: content.metadata
      }

      {:ok, build_response(opts, attrs)}
    end
  end

  defp build_response(opts, attrs) do
    passages = maybe_build_passages(attrs.content, attrs.title, attrs.final_url, opts[:citations])

    %{
      url: attrs.url,
      final_url: attrs.final_url,
      title: attrs.title,
      content: attrs.content,
      format: opts[:format],
      content_type: attrs.content_type,
      document_type: attrs.document_type,
      retrieved_at: retrieved_at(),
      estimated_tokens: estimate_tokens(attrs.content),
      original_estimated_tokens: attrs.original_estimated_tokens,
      truncated: attrs.truncated,
      filtered: attrs.filtered,
      focus_matches: attrs.focus_matches,
      cached: false,
      citations: %{enabled: opts[:citations]},
      passages: passages
    }
    |> maybe_put_metadata(attrs.metadata)
  end

  defp maybe_filter_content(content, opts) do
    case opts[:focus_terms] do
      [] ->
        {:ok, content, false, 0}

      terms ->
        sections = split_sections(content)
        matching_indexes = matching_section_indexes(sections, terms)
        window = max(opts[:focus_window] || 0, 0)
        kept_indexes = expand_focus_window(matching_indexes, window, length(sections))
        filtered_content = render_section_slice(sections, kept_indexes)

        {:ok, filtered_content, true, length(matching_indexes)}
    end
  end

  defp maybe_truncate(content, nil), do: {content, false, estimate_tokens(content)}

  defp maybe_truncate(content, max_content_tokens) when is_integer(max_content_tokens) and max_content_tokens > 0 do
    original_estimated_tokens = estimate_tokens(content)

    if original_estimated_tokens <= max_content_tokens do
      {content, false, original_estimated_tokens}
    else
      char_limit = max_content_tokens * 4
      truncated = String.slice(content, 0, char_limit) |> String.trim()
      {truncated, true, original_estimated_tokens}
    end
  end

  defp maybe_truncate(content, _other), do: {content, false, estimate_tokens(content)}

  defp maybe_build_passages(_content, _title, _url, false), do: []

  defp maybe_build_passages(content, title, url, true) do
    content
    |> split_sections()
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce({[], 0, 0}, fn section, {passages, cursor, index} ->
      start_char = cursor
      end_char = start_char + String.length(section)

      passage = %{
        index: index,
        start_char: start_char,
        end_char: end_char,
        text: section,
        title: title,
        url: url
      }

      {[passage | passages], end_char + 2, index + 1}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.take(50)
  end

  defp split_sections(content) do
    content
    |> String.split(~r/\n\s*\n+/, trim: true)
    |> case do
      [] -> [String.trim(content)]
      sections -> Enum.map(sections, &String.trim/1)
    end
  end

  defp retrieved_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp estimate_tokens(content) when is_binary(content) do
    div(String.length(content) + 3, 4)
  end

  defp estimate_tokens(_content), do: 0

  defp maybe_put_metadata(response, metadata) when metadata in [%{}, nil], do: response
  defp maybe_put_metadata(response, metadata), do: Map.put(response, :metadata, metadata)

  defp matching_section_indexes(sections, terms) do
    downcased_terms = Enum.map(terms, &String.downcase/1)

    sections
    |> Enum.with_index()
    |> Enum.flat_map(fn {section, index} ->
      if section_matches_term?(section, downcased_terms), do: [index], else: []
    end)
  end

  defp section_matches_term?(section, downcased_terms) do
    lowered = String.downcase(section)
    Enum.any?(downcased_terms, &String.contains?(lowered, &1))
  end

  defp expand_focus_window(matching_indexes, window, section_count) do
    matching_indexes
    |> Enum.flat_map(fn index -> (index - window)..(index + window) end)
    |> Enum.filter(&(&1 >= 0 and &1 < section_count))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp render_section_slice(sections, indexes) do
    indexes
    |> Enum.map(&Enum.at(sections, &1))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> String.trim()
  end
end
