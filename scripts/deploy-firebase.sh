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
npx --yes firebase-tools@14 deploy --only firestore --project halaqat-app-272ff
# Deploy one function at a time: startup CPU boosts can exceed small regional quotas.
mapfile -t function_names < <(GCLOUD_PROJECT=halaqat-app-272ff node -e 'const f=require("./functions/lib/index.js"); Object.keys(f).filter(k=>f[k]?.__endpoint).sort().forEach(k=>console.log(k))')
if [ "${#function_names[@]}" -eq 0 ]; then
  echo "No deployable functions found." >&2
  exit 1
fi
deploy_log="$(mktemp)"
trap 'rm -f "$deploy_log"' EXIT
for name in "${function_names[@]}"; do
  printf '\nDeploying %s\n' "$name"
  for attempt in 1 2 3; do
    if npx --yes firebase-tools@14 deploy --only "functions:$name" --project halaqat-app-272ff --non-interactive >"$deploy_log" 2>&1; then
      cat "$deploy_log"
      break
    else
      status=$?
      cat "$deploy_log"
      if [ "$attempt" -lt 3 ] && grep -qi 'Quota exceeded for total allowable CPU' "$deploy_log"; then
        echo "Regional CPU quota reached; waiting 60 seconds before retry."
        sleep 60
      else
        echo "Stopped at function: $name" >&2
        exit "$status"
      fi
    fi
  done
done
printf '\nBackend deployment finished. Web publication still requires a successful coordinated GitHub Pages deployment.\n'
