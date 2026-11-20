#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
usage() {
  echo 'Usage: ./scripts/run_test.sh [all|master|leaflet|geo|idw|terrain]'
  echo 'Logs and reports are saved under tests/results/.'
}
case ${1:-all} in
  -h|--help) usage; exit 0 ;;
  all|master|leaflet|geo|idw|terrain) target=${1:-all} ;;
  *) usage >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { usage >&2; exit 2; }
command -v Rscript >/dev/null || { echo 'Rscript is required.' >&2; exit 2; }
cd "$ROOT"
mkdir -p tests/results
report=$(mktemp -d "$ROOT/tests/results/run-XXXXXXXX")
echo "Report: ${report#"$ROOT/"}"
status=0
Rscript --vanilla tests/run_workflow.R "$target" "$report" >"$report/run.log" 2>&1 || status=$?
cat "$report/run.log"
echo "Exit status: $status"
exit "$status"
