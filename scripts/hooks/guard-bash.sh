#!/usr/bin/env bash
# Hook PreToolUse (Bash) : refuse les commandes destructrices ou qui contournent le harness.
set -uo pipefail

cmd="$(cat | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

deny() {
  echo "BLOQUÉ : $1 Commande : $cmd" >&2
  exit 2
}

case "$cmd" in
  *"git push"*)            deny "le push est fait par l'humain." ;;
  *"--no-verify"*)         deny "les vérifications ne se contournent pas." ;;
  *"git commit --amend"*)  deny "on ne réécrit pas un commit existant." ;;
  *"git reset --hard"*)    deny "perte de travail possible ; demande à l'humain." ;;
  *"git clean -f"*)        deny "suppression de fichiers non suivis ; demande à l'humain." ;;
  *"rm -rf /"*|*"rm -rf ~"*|*'rm -rf $HOME'*) deny "suppression dangereuse." ;;
  *".env"*)                deny "accès à un fichier de secrets." ;;
esac

exit 0
