#!/usr/bin/env bash
set -euo pipefail

state_home="${XDG_STATE_HOME:-${HOME:?HOME or XDG_STATE_HOME must be set}/.local/state}"
omarchy_dir="$state_home/omarchy"
plugin_dir="$omarchy_dir/timekeeper"
state_file="$plugin_dir/state.json"

if [[ -L "$omarchy_dir" || -L "$plugin_dir" || -L "$state_file" ]]; then
  printf '%s\n' "Refusing to clean Timekeeper data through a symlink." >&2
  exit 1
fi

if [[ -e "$state_file" ]]; then
  if [[ ! -f "$state_file" ]]; then
    printf '%s\n' "Refusing to remove a non-file at $state_file." >&2
    exit 1
  fi
  rm -- "$state_file"
fi

for temporary in "$plugin_dir"/state.json.* "$plugin_dir"/.state.json.*; do
  [[ -e "$temporary" || -L "$temporary" ]] || continue
  if [[ -L "$temporary" || ! -f "$temporary" ]]; then
    printf '%s\n' "Refusing to remove an unexpected entry: $temporary" >&2
    exit 1
  fi
  rm -- "$temporary"
done

if [[ -d "$plugin_dir" ]]; then
  rmdir -- "$plugin_dir" 2>/dev/null || printf '%s\n' "Kept non-empty directory: $plugin_dir" >&2
fi
