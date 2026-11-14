#!/usr/bin/env bash
# Run on YOUR PC, from inside the personal-site folder.
#   ./upload.sh           send the folder to the server + build + show what would change live (changes nothing live)
#   ./upload.sh apply     send + deploy (build + checks run first; asks for confirmation)
set -euo pipefail
cd "$(dirname "$0")"
[ -f .deploy.env ] && . ./.deploy.env   # holds SERVER=user@host; not in git, see .deploy.env.example
: "${SERVER:?set SERVER in .deploy.env (copy .deploy.env.example)}"
rsync -rlc --delete --exclude='.git/' --exclude='.DS_Store' --exclude='*.bak*' \
  --exclude='site/dist/' --exclude='site/out/' --exclude='__pycache__/' --exclude='.venv/' \
  --exclude='/_*/' --exclude='/.claude/' --exclude='/.gitattributes' --exclude='/.deploy.env*' --exclude='desktop.ini' \
  ./ "$SERVER:/opt/personal-site/"
ssh -t "$SERVER" "/opt/personal-site/deploy.sh ${1:-status}"
