defmodule JidoBrowser.Actions.SelectOption do
  @moduledoc """
  Jido Action for selecting an option from a dropdown.

  ## Usage with Jido Agent

      # In your agent's tool list
      tools: [JidoBrowser.Actions.SelectOption]

      # The agent can then call:
      # select_option(selector: "select#country", value: "US")
      # select_option(selector: "select#country", label: "United States")
      # select_option(selector: "select#country", index: 0)

  """

  use Jido.Action,
    name: "browser_select_option",
    description: "Select an option from a dropdown element",
    category: "Browser",
    tags: ["browser", "interaction", "select", "form", "web"],
    vsn: "1.0.0",
    schema: [
      selector: [type: :string, required: true, doc: "CSS selector for the select element"],
      value: [type: :string, doc: "Option value to select"],
      label: [type: :string, doc: "Option label/text to select"],
      index: [type: :integer, doc: "Option index to select (0-based)"]
    ]

  alias JidoBrowser.ActionHelpers
  alias JidoBrowser.Error

  @impl true
  def run(params, context) do
    with {:ok, session} <- ActionHelpers.get_session(context) do
      selector = params.selector
      script = build_select_script(params)

      case JidoBrowser.evaluate(session, script, []) do
        {:ok, updated_session, %{result: %{"selected" => true} = result}} ->
          {:ok, %{status: "success", selector: selector, result: result, session: updated_session}}

        {:ok, _updated_session, %{result: %{"selected" => false, "error" => error}}} ->
          {:error, Error.element_error("select_option", selector, error)}

        {:error, reason} ->
          {:error, Error.element_error("select_option", selector, reason)}
      end
    end
  end

  defp build_select_script(%{selector: selector, value: value}) when is_binary(value) do
    """
    (() => {
      const select = document.querySelector(#{inspect(selector)});
      if (!select) return {selected: false, error: 'Select element not found'};
      if (select.tagName !== 'SELECT') return {selected: false, error: 'Element is not a select'};

      select.value = #{inspect(value)};
      select.dispatchEvent(new Event('change', {bubbles: true}));
      return {selected: true, selector: #{inspect(selector)}, value: #{inspect(value)}};
    })()
    """
  end

  defp build_select_script(%{selector: selector, label: label}) when is_binary(label) do
    """
    (() => {
      const select = document.querySelector(#{inspect(selector)});
      if (!select) return {selected: false, error: 'Select element not found'};
      if (select.tagName !== 'SELECT') return {selected: false, error: 'Element is not a select'};

      const options = Array.from(select.options);
      const option = options.find(o => o.text === #{inspect(label)} || o.label === #{inspect(label)});
      if (!option) return {selected: false, error: 'Option with label not found'};

      select.value = option.value;
      select.dispatchEvent(new Event('change', {bubbles: true}));
      return {selected: true, selector: #{inspect(selector)}, label: #{inspect(label)}, value: option.value};
    })()
    """
  end

  defp build_select_script(%{selector: selector, index: index}) when is_integer(index) do
    """
    (() => {
      const select = document.querySelector(#{inspect(selector)});
      if (!select) return {selected: false, error: 'Select element not found'};
      if (select.tagName !== 'SELECT') return {selected: false, error: 'Element is not a select'};

      if (#{index} < 0 || #{index} >= select.options.length) {
        return {selected: false, error: 'Index out of range'};
      }

      select.selectedIndex = #{index};
      select.dispatchEvent(new Event('change', {bubbles: true}));
      return {selected: true, selector: #{inspect(selector)}, index: #{index}, value: select.value};
    })()
    """
  end

  defp build_select_script(%{selector: _selector}) do
    """
    (() => {
      return {selected: false, error: 'Must provide value, label, or index'};
    })()
    """
  end
end
