#!/usr/bin/env bash
# Lanza una sesión headless de Claude Code que invoca /quality-gate y guarda la traza completa.
# uso: run_gate.sh <modo: full|discover> <dir proyecto> <log jsonl> [PATH alternativo]
set -uo pipefail
mode="$1"; dir="$2"; log="$3"; altpath="${4:-}"

NOHUMAN="No hay ningún humano disponible para responder preguntas en esta sesión: si algo requiere aprobación, no lo hagas y déjalo como pendiente en el reporte."
if [[ "$mode" == full ]]; then
  prompt="/quality-gate
Tienes autorización para corregir fallos dentro del alcance del cambio. $NOHUMAN"
  args=(--permission-mode acceptEdits --allowedTools "Bash Read Edit Write Glob Grep Skill")
else
  prompt="/quality-gate
Ejecuta SOLO la fase Discover y emite el reporte: no ejecutes ninguna verificación (lint, tests, build) ni edites archivos. Para cada verificación candidata indica comando real y origen, y márcala skipped (motivo: solo Discover). Indica integraciones disponibles y nivel de riesgo con sus señales. $NOHUMAN"
  args=(--permission-mode default
        --allowedTools "Read Glob Grep Skill Bash(git status:*) Bash(git diff:*) Bash(git log:*) Bash(git symbolic-ref:*) Bash(git branch:*) Bash(ls:*) Bash(cat:*) Bash(command -v:*)"
        --disallowedTools "Edit Write NotebookEdit")
fi

cd "$dir" || exit 2
if [[ -n "$altpath" ]]; then export PATH="$altpath"; fi
start=$(date +%s)
claude -p "$prompt" --output-format stream-json --verbose --max-turns 80 "${args[@]}" > "$log" 2> "${log%.jsonl}.stderr"
rc=$?
echo "rc=$rc dur=$(( $(date +%s) - start ))s" > "${log%.jsonl}.meta"
