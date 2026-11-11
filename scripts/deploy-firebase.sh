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
# Deploy four functions at a time to avoid a burst of Cloud Run CPU allocations.
mapfile -t function_names < <(GCLOUD_PROJECT=halaqat-app-272ff node -e 'const f=require("./functions/lib/index.js"); Object.keys(f).filter(k=>f[k]?.__endpoint).sort().forEach(k=>console.log(k))')
if [ "${#function_names[@]}" -eq 0 ]; then
  echo "No deployable functions found." >&2
  exit 1
fi
for ((offset=0; offset<${#function_names[@]}; offset+=4)); do
  selected=()
  for name in "${function_names[@]:offset:4}"; do selected+=("functions:$name"); done
  only_functions="$(IFS=,; echo "${selected[*]}")"
  npx --yes firebase-tools@14 deploy --only "$only_functions" --project halaqat-app-272ff
done
printf '\nBackend deployment finished. Web publication still requires a successful coordinated GitHub Pages deployment.\n'
