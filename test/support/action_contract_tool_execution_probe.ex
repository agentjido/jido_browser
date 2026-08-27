defmodule Jido.Browser.ActionContractToolExecutionProbe do
  @moduledoc false

  use Jido.Action,
    name: "action_contract_tool_execution_probe",
    description: "Return validated parameters for action tool contract tests",
    schema: [
      required_count: [type: :integer, required: true, doc: "Required count"],
      label: [type: :string, default: "default-label", doc: "Optional label"]
    ]

  @impl true
  def run(params, _context), do: {:ok, params}
end
