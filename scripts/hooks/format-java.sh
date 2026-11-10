#!/usr/bin/env bash
# Hook PostToolUse (Edit|Write|MultiEdit) : formate le fichier Java modifié avec Spotless.
# Inactif tant que le wrapper Maven n'existe pas (avant l'étape 1 du plan).
# Code 2 = le formatage a échoué (souvent une erreur de syntaxe) : l'agent doit corriger.
set -uo pipefail

file="$(cat | jq -r '.tool_input.file_path // empty')"
case "$file" in *.java) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0

project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -x "$project/mvnw" ] || exit 0
cd "$project" || exit 0

if ! out="$(./mvnw -q spotless:apply -DspotlessFiles="$file" 2>&1)"; then
  echo "Formatage impossible pour $file : vérifie la syntaxe." >&2
  printf '%s\n' "$out" | tail -n 30 >&2
  exit 2
fi
exit 0
