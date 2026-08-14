#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage:
  build-plugin-package.sh --source Plugin.mactoolsplugin --output-dir dist [--zip]

This helper validates the directory shape and copies the package into dist. It does
not build an external plugin project; plugin repositories can call it after their
own xcodebuild step.
USAGE
}

SOURCE=""
OUTPUT_DIR=""
ZIP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE="${2:-}"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="${2:-}"
            shift 2
            ;;
        --zip)
            ZIP=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$SOURCE" || -z "$OUTPUT_DIR" ]]; then
    usage >&2
    exit 1
fi

[[ -d "$SOURCE" ]] || { echo "Package directory not found: $SOURCE" >&2; exit 1; }
[[ "$SOURCE" == *.mactoolsplugin ]] || { echo "Package must end with .mactoolsplugin" >&2; exit 1; }
[[ -f "$SOURCE/plugin.json" ]] || { echo "Missing plugin.json in $SOURCE" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
DEST="$OUTPUT_DIR/$(basename "$SOURCE")"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"

if [[ "$ZIP" == "1" ]]; then
    ZIP_PATH="$DEST.zip"
    rm -f "$ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$DEST" "$ZIP_PATH"
    echo "$ZIP_PATH"
else
    echo "$DEST"
fi
