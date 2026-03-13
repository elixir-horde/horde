defmodule UniformQuorumDistributionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "chooses one of the members" do
    member =
      ExUnitProperties.gen all(
                             node_id <- integer(1..100_000),
                             status <- StreamData.member_of([:alive, :dead, :shutting_down]),
                             name <- binary(),
                             pid <- atom(:alias)
                           ) do
        %{node_id: node_id, status: status, pid: pid, name: "A#{name}"}
      end

    check all(
            members <-
              uniq_list_of(member,
                min_length: 2,
                uniq_fun: fn %{node_id: node_id} -> node_id end
              ),
            identifier <- string(:alphanumeric)
          ) do
      child_spec = %{id: identifier, start: {identifier}}
      partition_a = members

      partition_b =
        members
        |> Enum.map(fn
          %{status: :alive} = member ->
            %{member | status: :dead}

          %{status: :dead} = member ->
            %{member | status: :alive}

          node_spec ->
            node_spec
        end)

      chosen_a = Horde.UniformQuorumDistribution.choose_node(child_spec, partition_a)

      chosen_b = Horde.UniformQuorumDistribution.choose_node(child_spec, partition_b)

      partitions_succeeded =
        [chosen_a, chosen_b]
        |> Enum.count(fn
          {:ok, _} -> 1
          {:error, _} -> false
        end)

      Enum.all?(members, fn
        %{status: :shutting_down} -> true
        _ -> false
      end)
      |> if do
        assert 0 == partitions_succeeded
      else
        assert 1 == partitions_succeeded
      end
    end
  end

  test "has_quorum? returns false for empty list" do
    refute Horde.UniformQuorumDistribution.has_quorum?([])
  end

  test "has_quorum? returns nil when all members are shutting_down" do
    members = [
      %{status: :shutting_down, name: :a},
      %{status: :shutting_down, name: :b},
      %{status: :shutting_down, name: :c}
    ]

    assert Horde.UniformQuorumDistribution.has_quorum?(members) == nil
  end

  test "has_quorum? returns true when majority is alive" do
    members = [
      %{status: :alive, name: :a},
      %{status: :alive, name: :b},
      %{status: :dead, name: :c}
    ]

    assert Horde.UniformQuorumDistribution.has_quorum?(members)
  end

  test "has_quorum? returns false when majority is dead" do
    members = [
      %{status: :alive, name: :a},
      %{status: :dead, name: :b},
      %{status: :dead, name: :c}
    ]

    refute Horde.UniformQuorumDistribution.has_quorum?(members)
  end

  test "choose_node returns quorum_not_met when no quorum" do
    members = [
      %{status: :alive, name: :a},
      %{status: :dead, name: :b},
      %{status: :dead, name: :c}
    ]

    assert {:error, :quorum_not_met} =
             Horde.UniformQuorumDistribution.choose_node(%{id: :test, start: {:test}}, members)
  end
end
