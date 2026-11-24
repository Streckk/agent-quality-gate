#!/usr/bin/env bash
# Lanza una sesión headless de Claude Code con el plugin cargado desde este repo (--plugin-dir),
# sin instalarlo ni tocar settings. uso: run_hooks_e2e.sh <proyecto> <log.jsonl> <prompt> [VAR=valor…]
set -uo pipefail
dir=$1; log=$2; prompt=$3; shift 3
REPO=$(cd "$(dirname "$0")/../.." && pwd -P)
cd "$dir" || exit 2
start=$(date +%s)
env "$@" claude -p "$prompt" --plugin-dir "$REPO" --output-format stream-json --verbose --max-turns 60 \
  --permission-mode acceptEdits --allowedTools "Bash Read Edit Write Glob Grep Skill" > "$log" 2> "${log%.jsonl}.stderr"
echo "rc=$? dur=$(( $(date +%s) - start ))s" > "${log%.jsonl}.meta"
