# NOW
- BENCHMARKS vs OG Horde
- recording registry meta
- cleaning up registry event log

# LATER
- process handoff
  - how to put power into the hands of users? ex, maybe you only want to persist state for some processes and not others, depending for example on how expensive the state was to build up.

- find a way to do batch inserts to speed up

- finish README
  - getting started guide

- write mix task to copy migrations into repo migrations folder

- optimize tables with indexes

- add note about listeners firing on every node

- use LISTEN / NOTIFY instead of polling in *Manager

## Considering
- Horde.Supervisor
  - I have seen this being requested a number of times. Sometimes people want to start a static list of processes and have them be uniformly distributed across their cluster. Perhaps we can meet this use case.
