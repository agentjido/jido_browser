# Run with: mix run example_state_persistence.exs

alias Jido.Browser

state_path = Path.expand("tmp/example-browser-state.json", __DIR__)
File.mkdir_p!(Path.dirname(state_path))

{:ok, session} = Browser.start_session()

try do
  {:ok, session, _nav_result} = Browser.navigate(session, "https://example.com")

  # Replace this script with your application's real login flow before saving state.
  {:ok, session, _eval_result} =
    Browser.evaluate(
      session,
      ~S/localStorage.setItem("example_auth_token", "token-from-example-script"); "ok"/
    )

  {:ok, _session, _save_result} = Browser.save_state(session, state_path)
  IO.puts("Saved browser state to #{state_path}")
after
  Browser.end_session(session)
end

{:ok, restored_session} = Browser.start_session()

try do
  {:ok, restored_session, _load_result} = Browser.load_state(restored_session, state_path)
  {:ok, restored_session, _nav_result} = Browser.navigate(restored_session, "https://example.com")

  {:ok, _session, eval_result} =
    Browser.evaluate(restored_session, ~S/localStorage.getItem("example_auth_token")/)

  IO.puts("Restored token: #{inspect(eval_result["result"] || eval_result[:result])}")
after
  Browser.end_session(restored_session)
end
