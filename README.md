# Horde
<!-- MDOC !-->

`Horde` is a distributed Supervisor and Registry.

This version of Horde reflects years of practical experience with Elixir and distributed systems. It introduces a refined architecture focused on stability, maintainability, and ease of operation, while keeping the API familiar to existing users.

One of the key design choices is the use of Postgres as the coordination back-end. Since Postgres is already a reliable singleton component in most stacks, this allows Horde to simplify its internal design and offer more predictable operational behavior.

Horde remains 99% API-compatible with `Elixir.DynamicSupervisor` and `Elixir.Registry`, and improves upon the API coverage offered in Horde.

At the moment, Horde supports Postgres as its back-end. If you are interested in using other databases, such as MariaDB, feel free to reach out.

Refer to `Horde.DynamicSupervisor` and `Horde.Registry` for detailed documentation.

## A Note on the Backend Migration

Horde has transitioned from the CRDT-based backend used in previous versions to a Postgres-backed coordination model. Postgres is already a trusted and reliable singleton in most production environments, and this shift allows Horde to offer more predictable behavior, simpler internals, and a more robust foundation overall.

If you prefer to continue using the CRDT-based approach, it remains fully available under the new package name **`horde-classic`**. This provides full continuity for existing setups while allowing new projects to benefit from the improved design.

Alongside the backend migration, we made several architectural refinements that significantly reduced internal complexity and improved performance, maintainability, and operational clarity.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `horde` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:horde, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/horde>.

