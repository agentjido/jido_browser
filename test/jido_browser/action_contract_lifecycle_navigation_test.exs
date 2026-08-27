defmodule Jido.Browser.ActionContractLifecycleNavigationTest do
  use ExUnit.Case, async: true

  import Jido.Browser.ActionContractAssertions

  alias Jido.Browser.Actions

  @contracts [
    %{
      module: Actions.StartSession,
      name: "browser_start_session",
      description: "Start a new browser session",
      schema: %{
        headless: %{type: :boolean, doc: "Run in headless mode"},
        timeout: %{type: :integer, doc: "Default timeout in ms"},
        adapter: %{type: :atom, doc: "Browser adapter module"},
        pool: %{type: :any, doc: "Optional warm session pool name"},
        checkout_timeout: %{type: :integer, doc: "Warm pool checkout timeout in ms"}
      }
    },
    %{
      module: Actions.EndSession,
      name: "browser_end_session",
      description: "End the current browser session",
      schema: %{}
    },
    %{
      module: Actions.GetStatus,
      name: "browser_get_status",
      description: "Get current session status (url, title, is_alive)",
      schema: %{}
    },
    %{
      module: Actions.PoolStatus,
      name: "browser_pool_status",
      description: "Return readiness and lifecycle status for a warm browser pool.",
      schema: %{
        pool: %{type: :any, doc: "Warm pool name or pid. Defaults to plugin pool state."}
      }
    },
    %{
      module: Actions.Navigate,
      name: "browser_navigate",
      description: "Navigate the browser to a URL",
      schema: %{
        url: %{type: :string, required: true, doc: "The URL to navigate to"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Back,
      name: "browser_back",
      description: "Navigate back in browser history",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Forward,
      name: "browser_forward",
      description: "Navigate forward in browser history",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.Reload,
      name: "browser_reload",
      description: "Reload the current page",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.GetUrl,
      name: "browser_get_url",
      description: "Get the current page URL",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.GetTitle,
      name: "browser_get_title",
      description: "Get the current page title",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.NewTab,
      name: "browser_new_tab",
      description: "Open a new browser tab",
      schema: %{
        url: %{type: :string, doc: "Optional URL to open in the new tab"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.CloseTab,
      name: "browser_close_tab",
      description: "Close a browser tab",
      schema: %{
        index: %{type: :integer, doc: "Optional tab index to close"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.SwitchTab,
      name: "browser_switch_tab",
      description: "Switch to another browser tab",
      schema: %{
        index: %{type: :integer, required: true, doc: "Tab index to activate"},
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.ListTabs,
      name: "browser_list_tabs",
      description: "List open browser tabs",
      schema: %{
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.SaveState,
      name: "browser_save_state",
      description: "Save browser session state to a file",
      schema: %{
        path: %{
          type: :string,
          required: true,
          doc: "Filesystem path where session state will be stored"
        },
        timeout: %{type: :integer, doc: "Timeout in milliseconds"}
      }
    },
    %{
      module: Actions.LoadState,
      name: "browser_load_state",
      description: "Load browser session state from a file",
      schema: %{
        path: %{
          type: :string,
          required: true,
          doc: "Filesystem path of the saved session state"
        },
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
