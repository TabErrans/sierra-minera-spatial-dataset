#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
usage() {
cat <<'HELP'
Usage: ./scripts/run.sh [--2d] [--3d] [--idw] [--csv] [--all] [--dem FILE]
Flags can be combined. Prerequisites run once in one R session.
--2d    Export the sample/element Leaflet map
--3d    Export the terrain HTML and PNG using prepared data
--idw   Export the IDW Leaflet map
--csv   Generate reusable spatial/chemical tables in data/processed/
--all   Run all four products
--dem   Use a local DEM for CSV elevation and IDW instead of downloading it
        Relative DEM paths are resolved from the caller's working directory.
Maps go to outputs/maps/. Existing products may be overwritten.

HELP
}
args=()
while (($#)); do
  case $1 in
    --help|-h) usage; exit 0 ;;
    --2d|--3d|--idw|--csv|--all) args+=("$1"); shift ;;
    --dem)
      [[ $# -ge 2 && -f $2 ]] || { echo '--dem requires an existing raster file.' >&2; exit 2; }
      args+=(--dem "$(realpath -- "$2")"); shift 2 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
((${#args[@]})) || { usage; exit 2; }
command -v Rscript >/dev/null || { echo 'Rscript is required.' >&2; exit 2; }
cd "$ROOT"
exec Rscript --vanilla scripts/run.R "${args[@]}"
