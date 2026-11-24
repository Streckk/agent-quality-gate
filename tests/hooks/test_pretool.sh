#!/usr/bin/env bash
# Hook PreToolUse: política de autoría en commits y aprobación humana para push/PR sin evidencia.
. "$(dirname "$0")/lib.sh"

RA=$(qg session id "$SID_A")
R=$(new_repo); printf 'a\n' > "$R/a.txt"; commit_all "$R" base
pt() { hook pre-tool-use.sh "$(ev_pretool "$SID_A" "${2:-$R}" "$1" "${3:-Bash}")" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1; }
decision() { case $1 in "") echo none ;; *'"permissionDecision":"deny"'*) echo deny ;; *'"permissionDecision":"ask"'*) echo ask ;; *'"permissionDecision":"allow"'*) echo ALLOW ;; *) echo other ;; esac; }
ALL_OUT=""
chk() {   # chk <esperado> <descripción> <comando> [cwd] [herramienta]
  local o; o=$(pt "$3" "${4:-}" "${5:-Bash}")
  ALL_OUT="$ALL_OUT$o"
  assert_eq "$(decision "$o")" "$1" "$2"
  json_ok "$o" || ko "$2: salida JSON inválida"
}

# --- A. Política de autoría
chk none "commit normal permitido (sin decisión)" 'git commit -m "feat: añade validación"'
chk deny "commit -m con Co-Authored-By" 'git commit -m "feat: x

Co-Authored-By: Claude <noreply@anthropic.com>"'
chk deny "commit con trailer en minúsculas" 'git commit -m "fix" -m "co-authored-by: bot <b@x>"'
chk deny "commit con heredoc multilínea" "git commit -m \"\$(cat <<'EOF'
docs: algo

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)\""
chk deny "commit con Generated-by: Codex" 'git commit -m "x" -m "Generated-by: Codex"'
chk deny "git -C dir commit con trailer" 'git -C /tmp/x commit -m "y

Co-authored-by: a <a@b>"'
chk none "mención sin dos puntos no es un trailer" 'git commit -m "docs: política sin Co-Authored-By ni créditos"'
chk none "argumentos con espacios y caracteres especiales" 'git commit -m "fix: \"citas\" $HOME * ; | & y ñ"'

printf 'feat: limpio\n' > "$R/msg-ok.txt"
printf 'feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n' > "$R/msg-bad.txt"
chk none "commit -F archivo limpio dentro del repo" 'git commit -F msg-ok.txt'
chk deny "commit -F archivo con trailer" 'git commit -F msg-bad.txt'
chk deny "commit --file=archivo con trailer" 'git commit --file=msg-bad.txt'
printf 'x\n' > "$TESTS_TMP/fuera.txt"
chk ask "commit -F archivo fuera del repo: no se revisa → ask" "git commit -F $TESTS_TMP/fuera.txt"
chk ask "commit -F con ruta no literal → ask" 'git commit -F "$MSGFILE"'
chk ask "commit -F inexistente → ask" 'git commit -F no-existe.txt'
chk none "commit -F - con heredoc limpio" "git commit -F - <<'EOF'
fix: limpio
EOF"
chk deny "commit -F - con heredoc con trailer" "git commit -F - <<'EOF'
fix

Co-Authored-By: x <x@y>
EOF"
chk ask "commit -C reutiliza mensaje → ask" 'git commit -C HEAD~1'

printf 'b\n' >> "$R/a.txt"; git -C "$R" add a.txt
git -C "$R" commit -q -m "wip

Co-Authored-By: Bot <b@x>"
chk deny "--amend --no-edit conservaría un trailer existente" 'git commit --amend --no-edit'
chk none "--amend con mensaje nuevo limpio" 'git commit --amend -m "fix: limpio"'

# --- B. Operaciones remotas
chk ask "git push sin evidencia → ask" 'git push origin main'
chk ask "gh pr create sin evidencia → ask" 'gh pr create --title "x" --body "y"'
O=$(pt 'git push')
assert_match "$O" 'qg status: missing' "push: el motivo indica el estado de la evidencia"
qg -C "$R" require --run-id "$RA" unit; qg -C "$R" run --run-id "$RA" unit -- true 2>/dev/null
chk none "git push con evidencia valid: sin decisión (los permisos normales siguen aplicando)" 'git push origin main'
chk none "gh pr create con evidencia valid" 'gh pr create --fill'
printf 'c\n' >> "$R/a.txt"
chk ask "git push con evidencia stale → ask" 'git push'

# --- Comandos irrelevantes y ambiguos
chk none "comando irrelevante" 'ls -la && npm test'
chk none "git status no es push ni commit" 'git status --short'
chk none "palabra 'pusher' no es push" 'git log --author=pusher'
chk ask "push dentro de bash -c se detecta (conservador)" 'bash -c "git push"'
chk none "herramienta distinta de Bash: no actúa" 'git push' "$R" Edit
chk none "git commit-tree no es commit" 'git commit-tree HEAD^{tree} -m "Co-Authored-By: x"'

# --- Activación y robustez
o=$(hook pre-tool-use.sh "$(ev_pretool "$SID_A" "$R" 'git push')" CLAUDE_PROJECT_DIR="$R")
assert_eq "$(decision "$o")" none "hooks desactivados: sin decisión"
o=$(hook pre-tool-use.sh "$(ev_pretool "$SID_A" "$R" 'git push')" CLAUDE_PROJECT_DIR="$R" QG_HOOKS=stop)
assert_eq "$(decision "$o")" none "QG_HOOKS=stop no activa pretool"
hook pre-tool-use.sh '{"session_id":"x","hook_event_name":"PreToolUse","tool_input":{"command":"git push"' CLAUDE_PROJECT_DIR="$R" QG_HOOKS=1 >/dev/null
assert_eq "$HOOK_RC/$(decision "$HOOK_OUT")" "0/none" "JSON malformado: exit 0 sin decisión"

assert_nomatch "$ALL_OUT" '"permissionDecision":"allow"' "nunca concede permisos (ninguna salida 'allow')"
assert_eq "$(git -C "$R" config --get user.name || echo sin-config-local)" "sin-config-local" "no modifica git config"

finish
