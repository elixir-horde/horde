# HordePro
<!-- MDOC !-->

`HordePro` is a Postgres-backed distributed supervisor and registry.

HordePro shares no code with Horde and has been completely re-written from the ground up, using what I learned from Horde and the better part of a decade in hindsight.

HordePro is backed by Postgres rather than the CRDT library that Horde uses (also written by me). I think this is a better choice for most users, since Postgres is already a singleton in most stacks, and this allows me to simplify things considerably. As such, HordePro should be more stable and easier to maintain and extend.

HordePro remains 99% API-compatible with `Elixir.DynamicSupervisor` and `Elixir.Registry`, and improves upon the API coverage offered in Horde.

Currently HordePro only supports Postgres as a back-end. If you are interested in running it against MariaDB or something else, please get in touch with me.

See `HordePro.DynamicSupervisor` and `HordePro.Registry` for documentation.

## Getting Started

Purchase a subscription to HordePro at Code Code Ship.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `horde_pro` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:horde_pro, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/horde_pro>.

