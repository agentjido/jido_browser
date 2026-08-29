defmodule Jido.Browser.ActionContractContentCompositeTest do
  use ExUnit.Case, async: false

  import Jido.Browser.ActionContractAssertions

  alias Jido.Browser.ActionContractInteractionQueryTest
  alias Jido.Browser.ActionContractLifecycleNavigationTest
  alias Jido.Browser.ActionContractToolExecutionProbe
  alias Jido.Browser.Actions

  @contracts [
    %{
      module: Actions.Snapshot,
      name: "browser_snapshot",
      description: "Get comprehensive LLM-friendly snapshot of the current page state",
      schema: %{
        include_links: %{type: :boolean, default: true, doc: "Include extracted links"},
        include_forms: %{type: :boolean, default: true, doc: "Include form field info"},
        include_headings: %{
          type: :boolean,
          default: true,
          doc: "Include heading structure"
        },
        max_content_length: %{
          type: :integer,
          default: 50_000,
          doc: "Truncate content at this length"
        },
        selector: %{
          type: :string,
          default: "body",
          doc: "CSS selector to scope extraction"
        }
      }
    },
    %{
      module: Actions.Screenshot,
      name: "browser_screenshot",
      description: "Take a screenshot of the current page",
      schema: %{
        full_page: %{
          type: :boolean,
          default: false,
          doc: "Capture the full scrollable page"
        },
        format: %{
          type: {:in, [:png]},
          default: :png,
          doc: "Image format (only PNG is currently supported)"
        },
        save_path: %{type: :string, doc: "Optional file path to save the screenshot"}
      }
    },
    %{
      module: Actions.ExtractContent,
      name: "browser_extract_content",
      description: "Extract content from the current page as markdown, HTML, or text",
      schema: %{
        selector: %{
          type: :string,
          default: "body",
          doc: "CSS selector to scope extraction"
        },
        format: %{
          type: {:in, [:markdown, :html, :text]},
          default: :markdown,
          doc: "Output format"
        }
      }
    },
    %{
      module: Actions.WebFetch,
      name: "web_fetch",
      description:
        "Fetch a URL over HTTP(S) with domain policy controls, Extractous-backed document extraction, " <>
          "optional focused filtering, approximate token caps, and citation-ready passages.",
      schema: %{
        url: %{type: :string, required: true, doc: "The URL to fetch"},
        format: %{
          type: {:in, [:markdown, :text, :html]},
          default: :markdown,
          doc: "Output format"
        },
        backend: %{
          type: {:in, [:req]},
          doc: "Req HTTP backend"
        },
        selector: %{type: :string, doc: "Optional CSS selector for HTML pages"},
        allowed_domains: %{
          type: {:list, :string},
          default: [],
          doc: "Allow-list of host or host/path rules"
        },
        blocked_domains: %{
          type: {:list, :string},
          default: [],
          doc: "Block-list of host or host/path rules"
        },
        allow_private_network: %{
          type: :boolean,
          default: false,
          doc: "Allow private network destinations"
        },
        focus_terms: %{
          type: {:list, :string},
          default: [],
          doc: "Terms used to filter the fetched document"
        },
        focus_window: %{
          type: :integer,
          default: 0,
          doc: "Paragraph window around each focus match"
        },
        max_content_tokens: %{
          type: :integer,
          doc: "Approximate token cap for returned content"
        },
        max_response_bytes: %{
          type: :timeout,
          default: 5 * 1024 * 1024,
          doc: "Positive response byte cap, or infinity to disable the cap"
        },
        citations: %{
          type: :boolean,
          default: false,
          doc: "Include citation-ready passage offsets"
        },
        cache: %{
          type: :boolean,
          default: true,
          doc: "Reuse cached fetch results when available"
        },
        timeout: %{type: :integer, doc: "Receive timeout in milliseconds"},
        require_known_url: %{
          type: :boolean,
          default: false,
          doc: "Require the URL to already be present in tool context"
        },
        known_urls: %{
          type: {:list, :string},
          default: [],
          doc: "Additional known URLs accepted for provenance checks"
        },
        max_uses: %{
          type: :integer,
          doc: "Maximum successful web fetch calls allowed in current skill state"
        }
      }
    },
    %{
      module: Actions.FetchRich,
      name: "fetch_rich",
      description:
        "Fetch a URL with normalized rich content, using fast HTTP retrieval first and optional browser fallback.",
      schema: %{
        url: %{type: :string, required: true, doc: "The URL to fetch"},
        format: %{
          type: {:in, [:markdown, :text, :html]},
          default: :markdown,
          doc: "Output format"
        },
        backend: %{type: {:in, [:req]}, doc: "Preferred Req HTTP backend"},
        http_backends: %{
          type: {:list, :atom},
          doc: "HTTP backend sequence, such as [:req]"
        },
        selector: %{
          type: :string,
          doc: "Optional CSS selector for HTML/browser extraction"
        },
        allowed_domains: %{
          type: {:list, :string},
          default: [],
          doc: "Allow-list of host or host/path rules"
        },
        blocked_domains: %{
          type: {:list, :string},
          default: [],
          doc: "Block-list of host or host/path rules"
        },
        allow_private_network: %{
          type: :boolean,
          default: false,
          doc: "Allow private network destinations"
        },
        focus_terms: %{
          type: {:list, :string},
          default: [],
          doc: "Terms used to filter fetched documents"
        },
        focus_window: %{
          type: :integer,
          default: 0,
          doc: "Paragraph window around each focus match"
        },
        max_content_tokens: %{
          type: :integer,
          doc: "Approximate token cap for returned content"
        },
        max_response_bytes: %{
          type: :timeout,
          default: 5 * 1024 * 1024,
          doc: "Positive response byte cap, or infinity to disable the cap"
        },
        citations: %{
          type: :boolean,
          default: false,
          doc: "Include citation-ready passage offsets"
        },
        cache: %{
          type: :boolean,
          default: true,
          doc: "Reuse cached fetch results when available"
        },
        timeout: %{type: :integer, doc: "Timeout in milliseconds"},
        browser_fallback: %{
          type: :boolean,
          default: false,
          doc: "Allow fallback to a browser session"
        },
        pool: %{
          type: :any,
          doc: "Optional warm browser pool used for browser fallback"
        },
        checkout_timeout: %{type: :integer, doc: "Warm pool checkout timeout in ms"},
        adapter: %{type: :atom, doc: "Browser adapter module for fallback"},
        headless: %{type: :boolean, doc: "Run fallback browser headless"},
        require_known_url: %{
          type: :boolean,
          default: false,
          doc: "Require the URL to be present in context"
        },
        known_urls: %{
          type: {:list, :string},
          default: [],
          doc: "Additional known URLs accepted for provenance"
        },
        max_uses: %{
          type: :integer,
          doc: "Maximum successful rich fetch calls allowed in current skill state"
        }
      }
    },
    %{
      module: Actions.ReadPage,
      name: "read_page",
      description:
        "Read a web page and return its content as markdown, text, or HTML. " <>
          "Manages browser session automatically.",
      schema: %{
        url: %{type: :string, required: true, doc: "The URL to read"},
        selector: %{
          type: :string,
          default: "body",
          doc: "CSS selector to scope extraction"
        },
        format: %{
          type: {:in, [:markdown, :text, :html]},
          default: :markdown,
          doc: "Output format"
        },
        pool: %{type: :any, doc: "Optional warm session pool name"},
        checkout_timeout: %{type: :integer, doc: "Warm pool checkout timeout in ms"},
        adapter: %{type: :atom, doc: "Browser adapter module"},
        headless: %{type: :boolean, doc: "Run in headless mode"},
        timeout: %{type: :integer, doc: "Default browser timeout in ms"}
      }
    },
    %{
      module: Actions.SnapshotUrl,
      name: "snapshot_url",
      description:
        "Navigate to a URL and return a comprehensive LLM-friendly snapshot " <>
          "including content, links, forms, and heading structure. Manages browser session automatically.",
      schema: %{
        url: %{type: :string, required: true, doc: "The URL to snapshot"},
        selector: %{
          type: :string,
          default: "body",
          doc: "CSS selector to scope extraction"
        },
        include_links: %{type: :boolean, default: true, doc: "Include extracted links"},
        include_forms: %{type: :boolean, default: true, doc: "Include form field info"},
        include_headings: %{
          type: :boolean,
          default: true,
          doc: "Include heading structure"
        },
        max_content_length: %{
          type: :integer,
          default: 50_000,
          doc: "Truncate content at this length"
        },
        pool: %{type: :any, doc: "Optional warm session pool name"},
        checkout_timeout: %{type: :integer, doc: "Warm pool checkout timeout in ms"},
        adapter: %{type: :atom, doc: "Browser adapter module"},
        headless: %{type: :boolean, doc: "Run in headless mode"},
        timeout: %{type: :integer, doc: "Default browser timeout in ms"}
      }
    },
    %{
      module: Actions.SearchWeb,
      name: "search_web",
      description:
        "Search the web using Brave Search API and return structured results " <>
          "with titles, URLs, and snippets.",
      schema: %{
        query: %{type: :string, required: true, doc: "Search query"},
        max_results: %{
          type: :integer,
          default: 10,
          doc: "Maximum number of results to return (max 20)"
        },
        country: %{
          type: :string,
          default: "us",
          doc: "Country code for results (e.g. us, gb, de)"
        },
        search_lang: %{
          type: :string,
          default: "en",
          doc: "Language code for results"
        },
        freshness: %{
          type: :string,
          doc: "Freshness filter: pd (24h), pw (week), pm (month), py (year)"
        }
      }
    }
  ]

  for contract <- @contracts do
    @contract contract

    test "freezes the #{contract.name} schema and tool contract" do
      assert_contract(@contract)
    end
  end

  test "covers every production browser action exactly once" do
    contract_modules =
      ActionContractLifecycleNavigationTest.contracts()
      |> Kernel.++(ActionContractInteractionQueryTest.contracts())
      |> Kernel.++(@contracts)
      |> Enum.map(& &1.module)

    production_modules = production_actions()

    assert length(contract_modules) == 40
    assert length(Enum.uniq(contract_modules)) == 40
    assert MapSet.new(contract_modules) == MapSet.new(production_modules)
  end

  test "uses static Zoi object input schemas for every production action" do
    for action <- production_actions() do
      assert %Zoi.Types.Map{fields: fields} = schema = action.schema()
      assert is_list(fields)
      refute schema_contains?(schema, &is_function/1)
      refute schema_contains?(schema, &match?(%Zoi.Types.Lazy{}, &1))
    end
  end

  test "web retrieval actions convert the tool infinity value before validation" do
    for action <- [Actions.WebFetch, Actions.FetchRich] do
      assert {:ok, params} =
               action.validate_params(%{
                 url: "https://example.com",
                 max_response_bytes: "infinity"
               })

      assert params.max_response_bytes == :infinity
    end
  end

  test "web retrieval actions reject non-positive response limits" do
    for action <- [Actions.WebFetch, Actions.FetchRich], value <- [0, -1] do
      assert {:error, %Jido.Browser.Error.InvalidError{} = error} =
               action.validate_params(%{
                 url: "https://example.com",
                 max_response_bytes: value
               })

      assert error.details.error_code == :invalid_input
      assert error.details.option == :max_response_bytes
      assert error.details.value == value
    end
  end

  @tag capture_log: true
  test "generated tool function converts and validates Action 2.x input" do
    tool = ActionContractToolExecutionProbe.to_tool()

    assert {:ok, result_json} =
             tool.function.(
               %{"required_count" => "7", "unknown_input" => "kept"},
               %{}
             )

    assert Jason.decode!(result_json) == %{
             "label" => "default-label",
             "required_count" => 7,
             "unknown_input" => "kept"
           }

    assert {:error, error_json} = tool.function.(%{"unknown_input" => "kept"}, %{})
    assert %{"error" => error_message} = Jason.decode!(error_json)
    assert error_message =~ "required :required_count option not found"
  end

  defp production_actions do
    :jido_browser
    |> Application.spec(:modules)
    |> Enum.filter(fn module ->
      String.starts_with?(Atom.to_string(module), "Elixir.Jido.Browser.Actions.") and
        Code.ensure_loaded?(module) and function_exported?(module, :__action_metadata__, 0)
    end)
  end

  defp schema_contains?(value, predicate) do
    predicate.(value) or schema_children_contain?(value, predicate)
  end

  defp schema_children_contain?(value, predicate) when is_map(value) do
    value
    |> Map.to_list()
    |> Enum.any?(fn {key, child} ->
      schema_contains?(key, predicate) or schema_contains?(child, predicate)
    end)
  end

  defp schema_children_contain?(value, predicate) when is_list(value) do
    Enum.any?(value, &schema_contains?(&1, predicate))
  end

  defp schema_children_contain?(value, predicate) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.any?(&schema_contains?(&1, predicate))
  end

  defp schema_children_contain?(_value, _predicate), do: false
end
