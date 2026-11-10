#!/usr/bin/env bash
# Hook PreToolUse (Read|Edit|Write|MultiEdit)
# - bloque tout accès aux secrets
# - bloque la modification de la spec validée et du harness (.claude/, scripts/hooks/)
# Code de sortie 2 = action refusée, le message stderr est renvoyé à l'agent.
set -uo pipefail

input="$(cat)"
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
[ -z "$file" ] && exit 0

project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
rel="${file#"$project"/}"
name="$(basename "$file")"

# 1. Secrets : ni lecture ni écriture
case "$name" in
  .env|.env.*|*.pem|*.key|*.p12|*.jks|*secret*|*credential*)
    echo "BLOQUÉ : '$rel' peut contenir un secret. L'agent ne lit ni n'écrit jamais de secrets." >&2
    exit 2 ;;
esac

# 2. Lecture autorisée pour le reste
[ "$tool" = "Read" ] && exit 0

# 3. Fichiers réservés à l'humain
case "$rel" in
  docs/spec/*)
    echo "BLOQUÉ : '$rel' est une spec validée. Propose la modification en texte ; l'humain l'appliquera." >&2
    exit 2 ;;
  .claude/*|scripts/hooks/*|AGENTS.md|CLAUDE.md)
    echo "BLOQUÉ : '$rel' fait partie du harness, modifiable uniquement par l'humain." >&2
    exit 2 ;;
esac

exit 0
