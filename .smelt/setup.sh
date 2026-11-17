# Prepares a fresh task workspace before Smelt starts the agent, so the agent
# does not spend turns or context on fetching and compiling dependencies.
# Run by Smelt with /bin/sh; it must write only ignored files (deps, _build).
set -eu

export MIX_ENV=test

mix deps.get
mix compile
