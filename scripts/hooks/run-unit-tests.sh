#!/usr/bin/env bash
# Hook Stop : avant que l'agent rende la main, les tests unitaires doivent passer
# (seulement si du code Java a changé depuis le dernier commit).
# Code 2 = l'agent ne peut pas s'arrêter et reçoit la sortie des tests.
set -uo pipefail

input="$(cat)"
# Évite une boucle infinie : si l'agent a déjà été relancé par ce hook, on le laisse s'arrêter.
[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

project="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -x "$project/mvnw" ] || exit 0
cd "$project" || exit 0

changed="$(git status --porcelain -- '*.java' 2>/dev/null)"
[ -z "$changed" ] && exit 0

if ! out="$(./mvnw -q test 2>&1)"; then
  echo "Tests unitaires en échec : corrige-les avant de rendre la main (ne désactive aucun test)." >&2
  printf '%s\n' "$out" | tail -n 60 >&2
  exit 2
fi
exit 0
