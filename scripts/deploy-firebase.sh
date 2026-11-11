#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
if [ "$(node -p 'Number(process.versions.node.split(".")[0])')" -lt 22 ]; then
  echo 'Node.js 22 or newer is required.' >&2
  exit 1
fi
cd functions
npm ci
npm run build
node --test test/shared_attendance.cjs
cd "$repo_root"
npx --yes firebase-tools@14 deploy --only functions,firestore --project halaqat-app-272ff
printf '\nBackend deployment finished. Web publication still requires a successful coordinated GitHub Pages deployment.\n'
