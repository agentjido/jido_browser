defmodule JidoBrowser.ActionsTest do
  use ExUnit.Case, async: false
  use Mimic

  alias JidoBrowser.Actions
  alias JidoBrowser.Session

  setup :set_mimic_global

  setup do
    session =
      Session.new!(%{
        adapter: JidoBrowser.Adapters.Vibium,
        connection: %{
          binary: "/usr/local/bin/clicker",
          headless: true,
          current_url: "https://example.com"
        }
      })

    context = %{session: session}
    {:ok, session: session, context: context}
  end

  describe "Navigation actions" do
    test "Back navigates history back", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "history.back"
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, %{status: "success", action: "back", session: ^session}} =
               Actions.Back.run(%{}, context)
    end

    test "Forward navigates history forward", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "history.forward"
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, %{status: "success", action: "forward", session: ^session}} =
               Actions.Forward.run(%{}, context)
    end

    test "Reload reloads the page", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "location.reload"
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, %{status: "success", action: "reload", session: ^session}} =
               Actions.Reload.run(%{}, context)
    end

    test "GetUrl returns current URL", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "location.href"
        {:ok, sess, %{result: "https://example.com/page"}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com/page", session: ^session}} =
               Actions.GetUrl.run(%{}, context)
    end

    test "GetTitle returns page title", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "document.title"
        {:ok, sess, %{result: "My Page Title"}}
      end)

      assert {:ok, %{status: "success", title: "My Page Title", session: ^session}} =
               Actions.GetTitle.run(%{}, context)
    end

    test "Navigate navigates to URL", %{context: context, session: session} do
      stub(JidoBrowser, :navigate, fn sess, url, _opts ->
        assert url == "https://example.com"
        {:ok, sess, %{url: url}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com", session: ^session}} =
               Actions.Navigate.run(%{url: "https://example.com"}, context)
    end
  end

  describe "Interaction actions" do
    test "Click clicks an element", %{context: context, session: session} do
      stub(JidoBrowser, :click, fn sess, selector, _opts ->
        assert selector == "button#submit"
        {:ok, sess, %{selector: selector}}
      end)

      assert {:ok, %{status: "success", selector: "button#submit", session: ^session}} =
               Actions.Click.run(%{selector: "button#submit"}, context)
    end

    test "Type types text into element", %{context: context, session: session} do
      stub(JidoBrowser, :type, fn sess, selector, text, _opts ->
        assert selector == "input#email"
        assert text == "test@example.com"
        {:ok, sess, %{selector: selector, text: text}}
      end)

      assert {:ok, %{status: "success", selector: "input#email", session: ^session}} =
               Actions.Type.run(%{selector: "input#email", text: "test@example.com"}, context)
    end

    test "Scroll scrolls by pixels", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "scrollBy"
        {:ok, sess, %{result: %{"scrolled" => true, "x" => 0, "y" => 500}}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{x: 0, y: 500}, context)
    end

    test "Scroll scrolls to direction", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "scrollTo" or script =~ "scrollHeight"
        {:ok, sess, %{result: %{"scrolled" => true, "direction" => "bottom"}}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{direction: :bottom}, context)
    end

    test "Scroll scrolls to element by selector", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "scrollIntoView"
        assert script =~ "#target"
        {:ok, sess, %{result: %{"scrolled" => true, "selector" => "#target"}}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Scroll.run(%{selector: "#target"}, context)
    end

    test "Hover dispatches mouse events", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "mouseover" or script =~ "mouseenter"
        {:ok, sess, %{result: %{"hovered" => true, "selector" => "#button"}}}
      end)

      assert {:ok, %{status: "success", selector: "#button", session: ^session}} =
               Actions.Hover.run(%{selector: "#button"}, context)
    end

    test "Focus focuses element", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "focus"
        {:ok, sess, %{result: %{"focused" => true, "selector" => "input#email"}}}
      end)

      assert {:ok, %{status: "success", selector: "input#email", session: ^session}} =
               Actions.Focus.run(%{selector: "input#email"}, context)
    end

    test "SelectOption selects by value", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"selected" => true, "value" => "US"}}}
      end)

      assert {:ok, %{status: "success", selector: "select#country", session: ^session}} =
               Actions.SelectOption.run(%{selector: "select#country", value: "US"}, context)
    end

    test "SelectOption selects by label", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"selected" => true, "label" => "United States", "value" => "US"}}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.SelectOption.run(
                 %{selector: "select#country", label: "United States"},
                 context
               )
    end

    test "SelectOption selects by index", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script =~ "selectedIndex"
        {:ok, sess, %{result: %{"selected" => true, "index" => 2, "value" => "UK"}}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.SelectOption.run(%{selector: "select#country", index: 2}, context)
    end
  end

  describe "Wait actions" do
    test "Wait sleeps for specified time" do
      start = System.monotonic_time(:millisecond)

      assert {:ok, %{status: "success", waited_ms: 50}} =
               Actions.Wait.run(%{ms: 50}, %{})

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed >= 45
    end

    test "WaitForSelector waits for element", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"found" => true, "elapsed" => 150}}}
      end)

      assert {:ok, %{status: "success", selector: "#loading", state: :hidden, session: ^session}} =
               Actions.WaitForSelector.run(
                 %{selector: "#loading", state: :hidden, timeout: 5000},
                 context
               )
    end

    test "WaitForNavigation waits for URL change", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"url" => "https://example.com/new", "elapsed" => 200}}}
      end)

      assert {:ok, %{status: "success", url: "https://example.com/new", session: ^session}} =
               Actions.WaitForNavigation.run(%{timeout: 5000}, context)
    end
  end

  describe "Query actions" do
    test "Query returns matching elements", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess,
         %{
           result: [
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
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: []}}
      end)

      assert {:ok, %{status: "success", count: 0, elements: [], session: ^session}} =
               Actions.Query.run(%{selector: ".nonexistent"}, context)
    end

    test "GetText returns element text", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: "Hello World"}}
      end)

      assert {:ok, %{status: "success", text: "Hello World", session: ^session}} =
               Actions.GetText.run(%{selector: "#message"}, context)
    end

    test "GetText returns multiple texts when all: true", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: ["First", "Second", "Third"]}}
      end)

      assert {:ok, %{status: "success", texts: ["First", "Second", "Third"], session: ^session}} =
               Actions.GetText.run(%{selector: "p", all: true}, context)
    end

    test "GetAttribute returns attribute value", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: "https://example.com"}}
      end)

      assert {:ok, %{status: "success", value: "https://example.com", session: ^session}} =
               Actions.GetAttribute.run(%{selector: "a#link", attribute: "href"}, context)
    end

    test "IsVisible checks element visibility", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"exists" => true, "visible" => true}}}
      end)

      assert {:ok, %{exists: true, visible: true, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#modal"}, context)
    end

    test "IsVisible returns false for hidden element", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"exists" => true, "visible" => false}}}
      end)

      assert {:ok, %{exists: true, visible: false, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#hidden-element"}, context)
    end

    test "IsVisible returns false for non-existent element", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"exists" => false, "visible" => false}}}
      end)

      assert {:ok, %{exists: false, visible: false, session: ^session}} =
               Actions.IsVisible.run(%{selector: "#nonexistent"}, context)
    end
  end

  describe "Content extraction actions" do
    test "Snapshot returns comprehensive page info", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess,
         %{
           result: %{
             "url" => "https://example.com",
             "title" => "Example Page",
             "content" => "Main content here",
             "links" => [%{"id" => "link_0", "text" => "Home", "href" => "/"}],
             "forms" => [],
             "headings" => [%{"level" => 1, "text" => "Welcome"}],
             "meta" => %{"viewport_height" => 720}
           }
         }}
      end)

      assert {:ok, result} = Actions.Snapshot.run(%{}, context)
      assert result.status == "success"
      assert result["url"] == "https://example.com"
      assert result["title"] == "Example Page"
      assert length(result["links"]) == 1
      assert result.session == session
    end

    test "ExtractContent returns page content", %{context: context, session: session} do
      stub(JidoBrowser, :extract_content, fn sess, _opts ->
        {:ok, sess, %{content: "# Hello World\n\nThis is the page content.", format: :markdown}}
      end)

      assert {:ok, %{status: "success", content: content, format: :markdown, session: ^session}} =
               Actions.ExtractContent.run(%{}, context)

      assert content =~ "Hello World"
    end

    test "ExtractContent returns HTML when format: :html", %{context: context, session: session} do
      stub(JidoBrowser, :extract_content, fn sess, opts ->
        assert opts[:format] == :html
        {:ok, sess, %{content: "<h1>Hello World</h1>", format: :html}}
      end)

      assert {:ok, %{status: "success", format: :html, session: ^session}} =
               Actions.ExtractContent.run(%{format: :html}, context)
    end

    test "Screenshot takes a screenshot", %{context: context, session: session} do
      png_bytes = <<137, 80, 78, 71, 13, 10, 26, 10>>

      stub(JidoBrowser, :screenshot, fn sess, _opts ->
        {:ok, sess, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, %{status: "success", mime: "image/png", size: 8, base64: _, session: ^session}} =
               Actions.Screenshot.run(%{}, context)
    end

    test "Screenshot takes full page screenshot", %{context: context, session: session} do
      png_bytes = <<137, 80, 78, 71>>

      stub(JidoBrowser, :screenshot, fn sess, opts ->
        assert opts[:full_page] == true
        {:ok, sess, %{bytes: png_bytes, mime: "image/png"}}
      end)

      assert {:ok, %{status: "success", session: ^session}} =
               Actions.Screenshot.run(%{full_page: true}, context)
    end
  end

  describe "Evaluate action" do
    test "Evaluate executes JavaScript", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, script, _opts ->
        assert script == "1 + 1"
        {:ok, sess, %{result: 2}}
      end)

      assert {:ok, %{status: "success", result: 2, session: ^session}} =
               Actions.Evaluate.run(%{script: "1 + 1"}, context)
    end

    test "Evaluate returns complex result", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"name" => "test", "count" => 42}}}
      end)

      assert {:ok, %{status: "success", result: %{"name" => "test", "count" => 42}, session: ^session}} =
               Actions.Evaluate.run(%{script: "({name: 'test', count: 42})"}, context)
    end
  end

  describe "Session actions" do
    test "StartSession starts a new session" do
      stub(JidoBrowser, :start_session, fn opts ->
        assert opts[:headless] == true

        {:ok,
         Session.new!(%{
           adapter: JidoBrowser.Adapters.Vibium,
           connection: %{port: opts[:port] || 9515},
           opts: Map.new(opts)
         })}
      end)

      assert {:ok, %{status: "success", session: %Session{}}} =
               Actions.StartSession.run(%{headless: true}, %{})
    end

    test "StartSession preserves explicit headless false" do
      stub(JidoBrowser, :start_session, fn opts ->
        assert opts[:headless] == false

        {:ok,
         Session.new!(%{
           adapter: JidoBrowser.Adapters.Vibium,
           connection: %{port: 9515},
           opts: Map.new(opts)
         })}
      end)

      assert {:ok, %{status: "success", session: %Session{}}} =
               Actions.StartSession.run(%{headless: false}, %{})
    end

    test "StartSession with custom adapter" do
      stub(JidoBrowser, :start_session, fn opts ->
        {:ok,
         Session.new!(%{
           adapter: opts[:adapter],
           connection: %{profile: "default"}
         })}
      end)

      assert {:ok, %{status: "success", session: %Session{}}} =
               Actions.StartSession.run(%{adapter: JidoBrowser.Adapters.Web}, %{})
    end

    test "EndSession ends the session", %{context: context} do
      stub(JidoBrowser, :end_session, fn _session ->
        :ok
      end)

      assert {:ok, %{status: "success", message: "Session ended"}} =
               Actions.EndSession.run(%{}, context)
    end

    test "GetStatus returns session info", %{context: context, session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"url" => "https://example.com", "title" => "Test"}}}
      end)

      assert {:ok, %{status: "success", alive: true, url: "https://example.com", session: ^session}} =
               Actions.GetStatus.run(%{}, context)
    end

    test "GetStatus returns dead session info on error", %{context: context} do
      stub(JidoBrowser, :evaluate, fn _session, _script, _opts ->
        {:error, :connection_closed}
      end)

      assert {:ok, %{status: "success", alive: false, url: nil}} =
               Actions.GetStatus.run(%{}, context)
    end
  end

  describe "Error handling" do
    test "Back returns error on failure", %{context: context} do
      stub(JidoBrowser, :evaluate, fn _session, _script, _opts ->
        {:error, :timeout}
      end)

      assert {:error, %JidoBrowser.Error.NavigationError{}} =
               Actions.Back.run(%{}, context)
    end

    test "Click returns error when element not found", %{context: context} do
      stub(JidoBrowser, :click, fn _session, _selector, _opts ->
        {:error, :element_not_found}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.Click.run(%{selector: "#nonexistent"}, context)
    end

    test "Navigate returns error on invalid URL", %{context: context} do
      stub(JidoBrowser, :navigate, fn _session, _url, _opts ->
        {:error, :invalid_url}
      end)

      assert {:error, %JidoBrowser.Error.NavigationError{}} =
               Actions.Navigate.run(%{url: "not-a-url"}, context)
    end

    test "Hover returns error when element not found", %{context: context, session: _session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"hovered" => false, "error" => "Element not found"}}}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.Hover.run(%{selector: "#nonexistent"}, context)
    end

    test "Focus returns error when element not found", %{context: context, session: _session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"focused" => false, "error" => "Element not found"}}}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.Focus.run(%{selector: "#nonexistent"}, context)
    end

    test "SelectOption returns error when element not found", %{context: context, session: _session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: %{"selected" => false, "error" => "Select element not found"}}}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.SelectOption.run(%{selector: "#nonexistent", value: "test"}, context)
    end

    test "GetText returns error when element not found", %{context: context, session: _session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: nil}}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.GetText.run(%{selector: "#nonexistent"}, context)
    end

    test "GetAttribute returns error when element not found", %{context: context, session: _session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: nil}}
      end)

      assert {:error, %JidoBrowser.Error.ElementError{}} =
               Actions.GetAttribute.run(%{selector: "#nonexistent", attribute: "href"}, context)
    end
  end

  describe "Context session resolution" do
    test "Actions use :session from context", %{session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{session: session})
    end

    test "Actions use :browser_session from context", %{session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{browser_session: session})
    end

    test "Actions use tool_context session", %{session: session} do
      stub(JidoBrowser, :evaluate, fn sess, _script, _opts ->
        {:ok, sess, %{result: nil}}
      end)

      assert {:ok, _} = Actions.Back.run(%{}, %{tool_context: %{session: session}})
    end

    test "Actions return error when no session in context" do
      assert {:error, %JidoBrowser.Error.InvalidError{message: "No browser session in context"}} =
               Actions.Back.run(%{}, %{})
    end
  end

  describe "Session state contract" do
    test "navigate then click uses updated session", %{context: context, session: _session} do
      stub(JidoBrowser, :navigate, fn sess, url, _opts ->
        updated = %{sess | connection: Map.put(sess.connection, :current_url, url)}
        {:ok, updated, %{url: url}}
      end)

      stub(JidoBrowser, :click, fn sess, selector, _opts ->
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
