defmodule Jido.Browser.ActionsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.Browser.Actions
  alias Jido.Browser.Session

  setup :set_mimic_global

  setup do
    session =
      Session.new!(%{
        adapter: Jido.Browser.Adapters.AgentBrowser,
        connection: %{
          binary: "/usr/local/bin/agent-browser",
          current_url: "https://example.com"
        },
        runtime: %{manager: self()},
        capabilities: %{native_snapshot: true}
      })

    {:ok, session: session, context: %{session: session}}
  end

  describe "navigation actions" do
    test "Back navigates history back", %{context: context, session: session} do
      stub(Jido.Browser, :back, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, %{status: "success", action: "back", session: ^session}} =
               Actions.Back.run(%{}, context)
    end

    test "Forward navigates history forward", %{context: context, session: session} do
      stub(Jido.Browser, :forward, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, %{status: "success", action: "forward", session: ^session}} =
               Actions.Forward.run(%{}, context)
    end

    test "Reload reloads the page", %{context: context, session: session} do
      stub(Jido.Browser, :reload, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, %{status: "success", action: "reload", session: ^session}} =
               Actions.Reload.run(%{}, context)
    end

    test "GetUrl returns current URL", %{context: context, session: session} do
      stub(Jido.Browser, :get_url, fn sess, _opts ->
        {:ok, sess, %{"url" => "https://example.com/page"}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com/page", session: ^session}} =
               Actions.GetUrl.run(%{}, context)
    end

    test "GetTitle returns page title", %{context: context, session: session} do
      stub(Jido.Browser, :get_title, fn sess, _opts ->
        {:ok, sess, %{"title" => "My Page Title"}}
      end)

      assert {:ok, %{status: "success", title: "My Page Title", session: ^session}} =
               Actions.GetTitle.run(%{}, context)
    end

    test "Navigate navigates to URL", %{context: context, session: session} do
      stub(Jido.Browser, :navigate, fn sess, url, _opts ->
        assert url == "https://example.com"
        {:ok, sess, %{url: url}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com", session: ^session}} =
               Actions.Navigate.run(%{url: "https://example.com"}, context)
    end
  end

  describe "interaction actions" do
    test "Click clicks an element", %{context: context, session: session} do
      stub(Jido.Browser, :click, fn sess, selector, _opts ->
        assert selector == "button#submit"
        {:ok, sess, %{selector: selector}}
      end)

      assert {:ok, %{status: "success", selector: "button#submit", session: ^session}} =
               Actions.Click.run(%{selector: "button#submit"}, context)
    end

    test "Type types text into element", %{context: context, session: session} do
      stub(Jido.Browser, :type, fn sess, selector, text, _opts ->
        assert selector == "input#email"
        assert text == "test@example.com"
        {:ok, sess, %{selector: selector, text: text}}
      end)

      assert {:ok, %{status: "success", selector: "input#email", session: ^session}} =
               Actions.Type.run(%{selector: "input#email", text: "test@example.com"}, context)
    end

    test "Scroll scrolls by pixels", %{context: context, session: session} do
      stub(Jido.Browser, :scroll, fn sess, opts ->
        assert opts[:x] == 0
        assert opts[:y] == 500
        {:ok, sess, %{"scrolled" => true, "x" => 0, "y" => 500}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{x: 0, y: 500}, context)
    end

    test "Scroll scrolls to direction", %{context: context, session: session} do
      stub(Jido.Browser, :scroll, fn sess, opts ->
        assert opts[:direction] == :bottom
        {:ok, sess, %{"scrolled" => true, "direction" => "bottom"}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{direction: :bottom}, context)
    end

    test "Scroll scrolls to element by selector", %{context: context, session: session} do
      stub(Jido.Browser, :scroll, fn sess, opts ->
        assert opts[:selector] == "#target"
        {:ok, sess, %{"scrolled" => true, "selector" => "#target"}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{selector: "#target"}, context)
    end

    test "Hover dispatches mouse events", %{context: context, session: session} do
      stub(Jido.Browser, :hover, fn sess, selector, _opts ->
        assert selector == "#button"
        {:ok, sess, %{"hovered" => true, "selector" => selector}}
      end)

      assert {:ok, %{status: "success", selector: "#button", session: ^session}} =
               Actions.Hover.run(%{selector: "#button"}, context)
    end

    test "Focus focuses element", %{context: context, session: session} do
      stub(Jido.Browser, :focus, fn sess, selector, _opts ->
        assert selector == "input#email"
        {:ok, sess, %{"focused" => true, "selector" => selector}}
      end)

      assert {:ok, %{status: "success", selector: "input#email", session: ^session}} =
               Actions.Focus.run(%{selector: "input#email"}, context)
    end

    test "SelectOption selects by value", %{context: context, session: session} do
      stub(Jido.Browser, :select_option, fn sess, selector, opts ->
        assert selector == "select#country"
        assert opts[:value] == "US"
        {:ok, sess, %{"selected" => true, "value" => "US"}}
      end)

      assert {:ok, %{status: "success", selector: "select#country", session: ^session}} =
               Actions.SelectOption.run(%{selector: "select#country", value: "US"}, context)
    end

    test "SelectOption selects by label", %{context: context, session: session} do
      stub(Jido.Browser, :select_option, fn sess, _selector, opts ->
        assert opts[:label] == "United States"
        {:ok, sess, %{"selected" => true, "label" => "United States", "value" => "US"}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.SelectOption.run(
                 %{selector: "select#country", label: "United States"},
                 context
               )
    end

    test "SelectOption selects by index", %{context: context, session: session} do
      stub(Jido.Browser, :select_option, fn sess, _selector, opts ->
        assert opts[:index] == 2
        {:ok, sess, %{"selected" => true, "index" => 2, "value" => "UK"}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.SelectOption.run(%{selector: "select#country", index: 2}, context)
    end
  end

  describe "wait actions" do
    test "Wait sleeps for specified time" do
      start = System.monotonic_time(:millisecond)

      assert {:ok, %{status: "success", waited_ms: 50}} =
               Actions.Wait.run(%{ms: 50}, %{})

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed >= 45
    end

    test "WaitForSelector waits for element", %{context: context, session: session} do
      stub(Jido.Browser, :wait_for_selector, fn sess, selector, opts ->
        assert selector == "#loading"
        assert opts[:state] == :hidden
        {:ok, sess, %{"found" => true, "elapsed" => 150}}
      end)

      assert {:ok, %{status: "success", selector: "#loading", state: :hidden, session: ^session}} =
               Actions.WaitForSelector.run(
                 %{selector: "#loading", state: :hidden, timeout: 5000},
                 context
               )
    end

    test "WaitForNavigation waits for URL change", %{context: context, session: session} do
      stub(Jido.Browser, :wait_for_navigation, fn sess, opts ->
        assert opts[:timeout] == 5000
        {:ok, sess, %{"url" => "https://example.com/new", "elapsed" => 200}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com/new", session: ^session}} =
               Actions.WaitForNavigation.run(%{timeout: 5000}, context)
    end
  end

  describe "query actions" do
    test "Query returns matching elements", %{context: context, session: session} do
      stub(Jido.Browser, :query, fn sess, selector, opts ->
        assert selector == "button"
        assert opts[:limit] == 10

        {:ok, sess,
         %{
           count: 1,
           elements: [
             %{
               "index" => 0,
               "tag" => "button",
               "id" => "submit",
               "classes" => ["btn"],
               "text" => "Submit"
             }
           ]
         }}
      end)

      assert {:ok, %{status: "success", count: 1, elements: [%{"tag" => "button"}], session: ^session}} =
               Actions.Query.run(%{selector: "button"}, context)
    end

    test "Query returns empty list when no elements found", %{context: context, session: session} do
      stub(Jido.Browser, :query, fn sess, _selector, _opts ->
        {:ok, sess, %{count: 0, elements: []}}
      end)

      assert {:ok, %{status: "success", count: 0, elements: [], session: ^session}} =
               Actions.Query.run(%{selector: ".nonexistent"}, context)
    end

    test "GetText returns element text", %{context: context, session: session} do
      stub(Jido.Browser, :get_text, fn sess, selector, opts ->
        assert selector == "#message"
        refute opts[:all]
        {:ok, sess, %{text: "Hello World"}}
      end)

      assert {:ok, %{status: "success", text: "Hello World", session: ^session}} =
               Actions.GetText.run(%{selector: "#message"}, context)
    end

    test "GetText returns multiple texts when all: true", %{context: context, session: session} do
      stub(Jido.Browser, :get_text, fn sess, _selector, opts ->
        assert opts[:all]
        {:ok, sess, %{texts: ["First", "Second", "Third"]}}
      end)

      assert {:ok, %{status: "success", texts: ["First", "Second", "Third"], session: ^session}} =
               Actions.GetText.run(%{selector: "p", all: true}, context)
    end

    test "GetAttribute returns attribute value", %{context: context, session: session} do
      stub(Jido.Browser, :get_attribute, fn sess, selector, attribute ->
        assert selector == "a#link"
        assert attribute == "href"
        {:ok, sess, %{value: "https://example.com"}}
      end)

      assert {:ok, %{status: "success", value: "https://example.com", session: ^session}} =
               Actions.GetAttribute.run(%{selector: "a#link", attribute: "href"}, context)
    end

    test "IsVisible checks element visibility", %{context: context, session: session} do
      stub(Jido.Browser, :is_visible, fn sess, _selector ->
        {:ok, sess, %{"exists" => true, "visible" => true}}
      end)

      assert {:ok, %{exists: true, visible: true, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#modal"}, context)
    end

    test "IsVisible returns false for hidden element", %{context: context, session: session} do
      stub(Jido.Browser, :is_visible, fn sess, _selector ->
        {:ok, sess, %{"exists" => true, "visible" => false}}
      end)

      assert {:ok, %{exists: true, visible: false, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#hidden-element"}, context)
    end

    test "IsVisible returns false for non-existent element", %{context: context, session: session} do
      stub(Jido.Browser, :is_visible, fn sess, _selector ->
        {:ok, sess, %{"exists" => false, "visible" => false}}
      end)

      assert {:ok, %{exists: false, visible: false, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#nonexistent"}, context)
    end
  end

  describe "content extraction actions" do
    test "Snapshot returns page snapshot info", %{context: context, session: session} do
      stub(Jido.Browser, :snapshot, fn sess, _opts ->
        {:ok, sess,
         %{
           "url" => "https://example.com",
           "title" => "Example Page",
           "snapshot" => "Main content here",
           "refs" => %{"@e1" => %{"role" => "link", "text" => "Home"}}
         }}
      end)

      assert {:ok, result} = Actions.Snapshot.run(%{}, context)
      assert result.status == "success"
      assert result["url"] == "https://example.com"
      assert result["title"] == "Example Page"
      assert result["refs"]["@e1"]["text"] == "Home"
      assert result.session == session
    end

    test "ExtractContent returns page content", %{context: context, session: session} do
      stub(Jido.Browser, :extract_content, fn sess, _opts ->
        {:ok, sess, %{content: "# Hello World\n\nThis is the page content.", format: :markdown}}
      end)

      assert {:ok, %{status: "success", content: content, format: :markdown, session: ^session}} =
               Actions.ExtractContent.run(%{}, context)

      assert content =~ "Hello World"
    end

    test "ExtractContent returns HTML when format: :html", %{context: context, session: session} do
      stub(Jido.Browser, :extract_content, fn sess, opts ->
        assert opts[:format] == :html
        {:ok, sess, %{content: "<h1>Hello World</h1>", format: :html}}
      end)

      assert {:ok, %{status: "success", format: :html, session: ^session}} =
               Actions.ExtractContent.run(%{format: :html}, context)
    end

    test "Screenshot takes a screenshot", %{context: context, session: session} do
      png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

      stub(Jido.Browser, :screenshot, fn sess, _opts ->
        {:ok, sess, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, %{status: "success", mime: "image/png", size: 8, base64: _, session: ^session}} =
               Actions.Screenshot.run(%{}, context)
    end
  end

  describe "session and browser management actions" do
    test "StartSession starts a new session" do
      stub(Jido.Browser, :start_session, fn opts ->
        assert opts[:headless] == true

        {:ok,
         Session.new!(%{
           adapter: Jido.Browser.Adapters.AgentBrowser,
           connection: %{binary: "/usr/local/bin/agent-browser"},
           runtime: %{manager: self()},
           capabilities: %{native_snapshot: true},
           opts: Map.new(opts)
         })}
      end)

      assert {:ok, %{status: "success", session: %Session{}}} =
               Actions.StartSession.run(%{headless: true}, %{})
    end

    test "StartSession preserves explicit headless false" do
      stub(Jido.Browser, :start_session, fn opts ->
        assert opts[:headless] == false

        {:ok,
         Session.new!(%{
           adapter: Jido.Browser.Adapters.AgentBrowser,
           connection: %{binary: "/usr/local/bin/agent-browser"},
           runtime: %{manager: self()},
           capabilities: %{native_snapshot: true},
           opts: Map.new(opts)
         })}
      end)

      assert {:ok, %{status: "success", session: %Session{}}} =
               Actions.StartSession.run(%{headless: false}, %{})
    end

    test "EndSession ends the session", %{context: context} do
      stub(Jido.Browser, :end_session, fn _session ->
        :ok
      end)

      assert {:ok, %{status: "success", message: "Session ended"}} =
               Actions.EndSession.run(%{}, context)
    end

    test "GetStatus returns session info", %{context: context, session: session} do
      stub(Jido.Browser, :get_status, fn sess ->
        {:ok, sess, %{alive: true, url: "https://example.com", title: "Test"}}
      end)

      assert {:ok, %{status: "success", alive: true, url: "https://example.com", session: ^session}} =
               Actions.GetStatus.run(%{}, context)
    end

    test "GetStatus returns dead session info on error", %{context: context, session: session} do
      stub(Jido.Browser, :get_status, fn _sess ->
        {:ok, session, %{alive: false, url: nil, title: nil}}
      end)

      assert {:ok, %{status: "success", alive: false, url: nil}} =
               Actions.GetStatus.run(%{}, context)
    end

    test "SaveState saves state to disk", %{context: context, session: session} do
      stub(Jido.Browser, :save_state, fn sess, path, _opts ->
        assert path == "/tmp/state.json"
        {:ok, sess, %{saved: true}}
      end)

      assert {:ok, %{status: "success", path: "/tmp/state.json", session: ^session}} =
               Actions.SaveState.run(%{path: "/tmp/state.json"}, context)
    end

    test "LoadState loads state from disk", %{context: context, session: session} do
      stub(Jido.Browser, :load_state, fn sess, path, _opts ->
        assert path == "/tmp/state.json"
        {:ok, sess, %{loaded: true}}
      end)

      assert {:ok, %{status: "success", path: "/tmp/state.json", session: ^session}} =
               Actions.LoadState.run(%{path: "/tmp/state.json"}, context)
    end

    test "ListTabs returns tabs", %{context: context, session: session} do
      stub(Jido.Browser, :list_tabs, fn sess, _opts ->
        {:ok, sess, %{tabs: [%{"index" => 0, "url" => "https://example.com"}]}}
      end)

      assert {:ok, %{status: "success", tabs: [_], session: ^session}} =
               Actions.ListTabs.run(%{}, context)
    end

    test "NewTab opens a tab", %{context: context, session: session} do
      stub(Jido.Browser, :new_tab, fn sess, url, _opts ->
        assert url == "https://example.com/new"
        {:ok, sess, %{index: 1, url: url}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com/new", session: ^session}} =
               Actions.NewTab.run(%{url: "https://example.com/new"}, context)
    end

    test "SwitchTab activates a tab", %{context: context, session: session} do
      stub(Jido.Browser, :switch_tab, fn sess, index, _opts ->
        assert index == 1
        {:ok, sess, %{index: index}}
      end)

      assert {:ok, %{status: "success", index: 1, session: ^session}} =
               Actions.SwitchTab.run(%{index: 1}, context)
    end

    test "CloseTab closes a tab", %{context: context, session: session} do
      stub(Jido.Browser, :close_tab, fn sess, index, _opts ->
        assert index == 1
        {:ok, sess, %{closed: true, index: index}}
      end)

      assert {:ok, %{status: "success", index: 1, session: ^session}} =
               Actions.CloseTab.run(%{index: 1}, context)
    end

    test "Console returns console messages", %{context: context, session: session} do
      stub(Jido.Browser, :console, fn sess, _opts ->
        {:ok, sess, %{messages: [%{"level" => "info", "text" => "ready"}]}}
      end)

      assert {:ok, %{status: "success", messages: [_], session: ^session}} =
               Actions.Console.run(%{}, context)
    end

    test "Errors returns browser errors", %{context: context, session: session} do
      stub(Jido.Browser, :errors, fn sess, _opts ->
        {:ok, sess, %{errors: [%{"message" => "boom"}]}}
      end)

      assert {:ok, %{status: "success", errors: [_], session: ^session}} =
               Actions.Errors.run(%{}, context)
    end
  end

  describe "error handling" do
    test "Back returns error on failure", %{context: context} do
      stub(Jido.Browser, :back, fn _session, _opts ->
        {:error, :timeout}
      end)

      assert {:error, %Jido.Browser.Error.NavigationError{}} =
               Actions.Back.run(%{}, context)
    end

    test "Click returns error when element not found", %{context: context} do
      stub(Jido.Browser, :click, fn _session, _selector, _opts ->
        {:error, :element_not_found}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.Click.run(%{selector: "#nonexistent"}, context)
    end

    test "Navigate returns error on invalid URL", %{context: context} do
      stub(Jido.Browser, :navigate, fn _session, _url, _opts ->
        {:error, :invalid_url}
      end)

      assert {:error, %Jido.Browser.Error.NavigationError{}} =
               Actions.Navigate.run(%{url: "not-a-url"}, context)
    end

    test "Hover returns error when element not found", %{context: context, session: session} do
      stub(Jido.Browser, :hover, fn _sess, _selector, _opts ->
        {:ok, session, %{"hovered" => false, "error" => "Element not found"}}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.Hover.run(%{selector: "#nonexistent"}, context)
    end

    test "Focus returns error when element not found", %{context: context, session: session} do
      stub(Jido.Browser, :focus, fn _sess, _selector, _opts ->
        {:ok, session, %{"focused" => false, "error" => "Element not found"}}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.Focus.run(%{selector: "#nonexistent"}, context)
    end

    test "SelectOption returns error when element not found", %{context: context, session: session} do
      stub(Jido.Browser, :select_option, fn _sess, _selector, _opts ->
        {:ok, session, %{"selected" => false, "error" => "Select element not found"}}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.SelectOption.run(%{selector: "#nonexistent", value: "test"}, context)
    end

    test "GetText returns error when element not found", %{context: context, session: session} do
      stub(Jido.Browser, :get_text, fn _sess, _selector, _opts ->
        {:ok, session, %{text: nil}}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.GetText.run(%{selector: "#nonexistent"}, context)
    end

    test "GetAttribute returns error when element not found", %{context: context, session: session} do
      stub(Jido.Browser, :get_attribute, fn _sess, _selector, _attribute ->
        {:ok, session, %{value: nil}}
      end)

      assert {:error, %Jido.Browser.Error.ElementError{}} =
               Actions.GetAttribute.run(%{selector: "#nonexistent", attribute: "href"}, context)
    end
  end

  describe "context session resolution" do
    test "Actions use :session from context", %{session: session} do
      stub(Jido.Browser, :back, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{session: session})
    end

    test "Actions use :browser_session from context", %{session: session} do
      stub(Jido.Browser, :back, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{browser_session: session})
    end

    test "Actions use tool_context session", %{session: session} do
      stub(Jido.Browser, :back, fn sess, _opts ->
        {:ok, sess, %{ok: true}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{tool_context: %{session: session}})
    end

    test "Actions return error when no session in context" do
      assert {:error, %Jido.Browser.Error.InvalidError{message: "No browser session in context"}} =
               Actions.Back.run(%{}, %{})
    end
  end

  describe "session state contract" do
    test "navigate then click uses updated session", %{context: context, session: _session} do
      stub(Jido.Browser, :navigate, fn sess, url, _opts ->
        updated = %{sess | connection: Map.put(sess.connection, :current_url, url)}
        {:ok, updated, %{url: url}}
      end)

      stub(Jido.Browser, :click, fn sess, selector, _opts ->
        assert sess.connection.current_url == "https://example.com"
        {:ok, sess, %{selector: selector, clicked: true}}
      end)

      {:ok, %{session: nav_session}} =
        Actions.Navigate.run(%{url: "https://example.com"}, context)

      {:ok, %{session: click_session}} =
        Actions.Click.run(%{selector: "button"}, %{session: nav_session})

      assert click_session.connection.current_url == "https://example.com"
    end
  end
end
