defmodule Gong.BDD.InstructionRegistry do
  @moduledoc "Gong BDD 指令注册表入口"

  @spec fetch(atom(), :v1 | :v2) :: {:ok, map()} | :error
  def fetch(name, version \\ :v1) do
    Map.fetch(specs(version), name)
  end

  @spec all(:v1 | :v2) :: [map()]
  def all(version \\ :v1) do
    specs(version) |> Map.values() |> Enum.sort_by(& &1.name)
  end

  @spec specs(:v1 | :v2) :: map()
  def specs(:v1) do
    %{}
    |> merge_specs!(Gong.BDD.InstructionRegistries.Common.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Tools.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Agent.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Hook.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Tape.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Compaction.specs(:v1))
    |> merge_specs!(Gong.BDD.InstructionRegistries.Generated.specs(:v1))
  end

  def specs(:v2), do: specs(:v1)

  defp merge_specs!(base, additions) do
    Map.merge(base, additions)
  end
end
