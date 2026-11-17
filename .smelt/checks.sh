# courier's gate checks, run by Smelt with /bin/sh from a task workspace
# (a fresh worktree: no deps or build yet). Needs a local PostgreSQL.
#
# A step that passes prints one line; a step that fails prints its whole
# output and stops the script. Agents read this output, so it stays short.
set -eu

export MIX_ENV=test

step() {
  name=$1
  shift

  if output=$("$@" 2>&1); then
    echo "ok: $name"
  else
    status=$?
    echo "FAILED: $name (exit $status)"
    echo "$output"
    exit "$status"
  fi
}

step "deps.get" mix deps.get
step "unused deps" mix deps.unlock --check-unused
step "compile" mix compile --warnings-as-errors
step "format" mix format --check-formatted
step "test" mix test
