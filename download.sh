#!/usr/bin/env bash
# Run on YOUR PC, from inside the personal-site folder.
# Pulls the server copy (/opt/personal-site) into this folder, e.g. after Claude edited the site on the server.
# Overwrites your local copies of those files; commit first if you use git.
set -euo pipefail
cd "$(dirname "$0")"
[ -f .deploy.env ] && . ./.deploy.env   # holds SERVER=user@host; not in git, see .deploy.env.example
: "${SERVER:?set SERVER in .deploy.env (copy .deploy.env.example)}"
rsync -rlcv --exclude='site/dist/' --exclude='site/out/' --exclude='__pycache__/' --exclude='*.bak*' \
  "$SERVER:/opt/personal-site/" ./
