#!/usr/bin/env bash
# Full real UI check/tests, plus exact canonical domain sources in a minimal native module.
set -euo pipefail
ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
ROUND="$(dirname "$ROOT")"
ENVIRONMENT="${MOONCAST_ENVIRONMENT:-/workspace/scratch/665adc5202cf/.moonsuite-background/build-readiness-20261011T131950/environment.sh}"
export WORKER_ROOT="${MOONCAST_ROLL_WORKER:-$ROUND/worker}"
source "$ENVIRONMENT"
RABBITA="${MOONCAST_RABBITA_CACHE:-/workspace/scratch/665adc5202cf/.moonsuite-background/release-blockers-20261012T095200/sources/moonproj/.mooncakes/moonbit-community/rabbita}"
X="${MOONCAST_X_CACHE:-/workspace/scratch/665adc5202cf/.moonsuite-background/role-workflows-r571-575-20261012T134405/r572/source/.mooncakes/moonbitlang/x}"
verify_version() {
  python3 - "$1" "$2" <<'CHECK'
import json, pathlib, re, sys
p = pathlib.Path(sys.argv[1])
if (p / "moon.mod.json").exists():
    actual = json.loads((p / "moon.mod.json").read_text())["version"]
else:
    actual = re.search(r'version\s*=\s*"([^"]+)"', (p / "moon.mod").read_text()).group(1)
assert actual == sys.argv[2], (p, actual, sys.argv[2])
CHECK
}
verify_version "$RABBITA" 0.12.4
verify_version "$X" 0.4.40
UI="$ROOT/ui/rabbita-mooncast"
reserve() {
  local available
  available="$(df --output=avail -B1 "$WORKER_ROOT" | tail -1 | tr -d ' ')"
  (( available >= 4294967296 )) || { echo "Need 4 GiB free reserve" >&2; exit 1; }
  (( $(du -sb "$WORKER_ROOT" | cut -f1) < 250000000 )) || { echo "Worker reached 250 MB build budget" >&2; exit 1; }
}
run() {
  local name="$1"; shift
  if "$@" > "$WORKER_ROOT/reports/$name.log" 2>&1; then
    tail -1 "$WORKER_ROOT/reports/$name.log"
  else
    tail -80 "$WORKER_ROOT/reports/$name.log"; return 1
  fi
}
reserve
# Frozen Moon cannot register fresh per-package symlinks. Materialize the
# already-approved exact package bytes locally; never write through a cache link.
for directory in "$UI/.mooncakes" "$UI/.mooncakes/moonbit-community" "$UI/.mooncakes/moonbitlang"; do
  [[ ! -L "$directory" ]] || { echo "Refusing to modify linked modules directory: $directory" >&2; exit 1; }
done
mkdir -p "$UI/.mooncakes/moonbit-community" "$UI/.mooncakes/moonbitlang" "$WORKER_ROOT/reports"
materialize_cache() {
  local cache="$1" destination="$2" version="$3"
  if [[ -L "$destination" ]]; then
    [[ "$(readlink -f "$destination")" == "$(readlink -f "$cache")" ]] || {
      echo "Refusing to replace an unrelated cache link: $destination" >&2; exit 1;
    }
    # Only remove this runner's exact per-package link, never its target.
    rm -- "$destination"
  fi
  if [[ ! -e "$destination" ]]; then
    cp -aL -- "$cache" "$destination"
  fi
  verify_version "$destination" "$version"
}
materialize_cache "$RABBITA" "$UI/.mooncakes/moonbit-community/rabbita" 0.12.4
materialize_cache "$X" "$UI/.mooncakes/moonbitlang/x" 0.4.40
reserve
cd "$UI"
run ui-check moon check --frozen --target js --target-dir "$WORKER_ROOT/ui-build"
run editor-tests moon test --frozen --target js --target-dir "$WORKER_ROOT/ui-build" editor
run shared-tests moon test --frozen --target js --target-dir "$WORKER_ROOT/ui-build" shared
reserve
# This package has no external dependencies. Keep root module provider dependencies
# outside this narrowly scoped reducer test rather than replacing their versions.
mkdir -p "$WORKER_ROOT/native-domain/editor/domain"
cp "$ROOT/editor/domain/"* "$WORKER_ROOT/native-domain/editor/domain/"
printf 'name = "vectie/mooncast"\npreferred_target = "native"\n' > "$WORKER_ROOT/native-domain/moon.mod"
cd "$WORKER_ROOT/native-domain"
run native-domain-tests flock "$MOON_NATIVE_LOCK" moon test --frozen --target native --target-dir "$WORKER_ROOT/native-build" -j 1 --release --strip editor/domain
reserve
echo "Rolling cut: UI, planner, canonical reducer, undo/redo and stale guards passed."
