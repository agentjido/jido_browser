defmodule Jido.Browser.ActionContractInteractionQueryTest do
  use ExUnit.Case, async: true

  import Jido.Browser.ActionContractAssertions

  alias Jido.Browser.Actions

  @contracts [
    %{
      module: Actions.Click,
      name: "browser_click",
      description: "Click an element in the browser",
      schema: %{
        selector: %{
          type: :string,
          required: true,
          doc: "CSS selector for the element to click"
        },
        text: %{
          type: :string,
          doc: "Optional text content to match within the selector"
        },
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Type,
      name: "browser_type",
      description: "Type text into an element in the browser",
      schema: %{
        selector: %{
          type: :string,
          required: true,
          doc: "CSS selector for the input element"
        },
        text: %{type: :string, required: true, doc: "Text to type into the element"},
        clear: %{type: :boolean, default: false, doc: "Clear the field before typing"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Hover,
      name: "browser_hover",
      description: "Hover over an element in the browser",
      schema: %{
        selector: %{
          type: :string,
          required: true,
          doc: "CSS selector for the element to hover"
        },
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Focus,
      name: "browser_focus",
      description: "Focus on an element in the browser",
      schema: %{
        selector: %{
          type: :string,
          required: true,
          doc: "CSS selector for the element to focus"
        },
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Scroll,
      name: "browser_scroll",
      description: "Scroll the page by pixels, to preset positions, or to an element",
      schema: %{
        x: %{type: :integer, doc: "Horizontal scroll pixels"},
        y: %{type: :integer, doc: "Vertical scroll pixels"},
        direction: %{
          type: {:in, [:up, :down, :top, :bottom]},
          doc: "Preset scroll direction"
        },
        selector: %{type: :string, doc: "CSS selector to scroll element into view"}
      }
    },
    %{
      module: Actions.SelectOption,
      name: "browser_select_option",
      description: "Select an option from a dropdown element",
      schema: %{
        selector: %{
          type: :string,
          required: true,
          doc: "CSS selector for the select element"
        },
        value: %{type: :string, doc: "Option value to select"},
        label: %{type: :string, doc: "Option label/text to select"},
        index: %{type: :integer, doc: "Option index to select (0-based)"}
      }
    },
    %{
      module: Actions.Wait,
      name: "browser_wait",
      description: "Wait for a specified number of milliseconds",
      schema: %{
        ms: %{type: :integer, required: true, doc: "Milliseconds to wait"}
      }
    },
    %{
      module: Actions.WaitForSelector,
      name: "browser_wait_for_selector",
      description: "Wait for an element to appear, disappear, or change visibility state",
      schema: %{
        selector: %{type: :string, required: true, doc: "CSS selector to wait for"},
        state: %{
          type: {:in, [:attached, :visible, :hidden, :detached]},
          default: :visible,
          doc: "State to wait for: :attached, :visible, :hidden, or :detached"
        },
        timeout: %{
          type: :integer,
          default: 30_000,
          doc: "Maximum wait time in milliseconds"
        }
      }
    },
    %{
      module: Actions.WaitForNavigation,
      name: "browser_wait_for_navigation",
      description: "Wait for page navigation to complete",
      schema: %{
        url: %{type: :string, doc: "URL pattern to match (substring match)"},
        timeout: %{
          type: :integer,
          default: 30_000,
          doc: "Maximum wait time in milliseconds"
        }
      }
    },
    %{
      module: Actions.Query,
      name: "browser_query",
      description: "Query for elements matching a CSS selector",
      schema: %{
        selector: %{type: :string, required: true, doc: "CSS selector to query"},
        limit: %{type: :integer, default: 10, doc: "Maximum number of elements to return"}
      }
    },
    %{
      module: Actions.GetText,
      name: "browser_get_text",
      description: "Get text content of an element",
      schema: %{
        selector: %{type: :string, required: true, doc: "CSS selector for the element"},
        all: %{
          type: :boolean,
          default: false,
          doc: "Get text from all matching elements"
        }
      }
    },
    %{
      module: Actions.GetAttribute,
      name: "browser_get_attribute",
      description: "Get an attribute value from an element",
      schema: %{
        selector: %{type: :string, required: true, doc: "CSS selector for the element"},
        attribute: %{type: :string, required: true, doc: "Attribute name to get"}
      }
    },
    %{
      module: Actions.IsVisible,
      name: "browser_is_visible",
      description: "Check if an element is visible",
      schema: %{
        selector: %{type: :string, required: true, doc: "CSS selector for the element"}
      }
    },
    %{
      module: Actions.Evaluate,
      name: "browser_evaluate",
      description: "Execute JavaScript in the browser and return the result",
      schema: %{
        script: %{type: :string, required: true, doc: "JavaScript code to execute"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Console,
      name: "browser_console",
      description: "Read browser console messages",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Errors,
      name: "browser_errors",
      description: "Read browser runtime errors",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    }
  ]

  def contracts, do: @contracts

  for contract <- @contracts do
    @contract contract

    test "freezes the #{contract.name} schema and tool contract" do
      assert_contract(@contract)
    end
  end
end
