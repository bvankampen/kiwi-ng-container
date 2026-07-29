#!/usr/bin/env bash

# build-image.sh - Build an OpenSUSE Leap 15.6 OS image using KIWI NG in a container.
# Configurable container engine (docker or podman).
# Sourced from reference guide: https://docs.apps.rancher.io/reference-guides/kiwi

set -euo pipefail

# Default values
DEFAULT_ENGINE="docker"
DEFAULT_PROFILE="Cloud"
DEFAULT_BOX="leap"
DEFAULT_OUT_DIR="./target_image"
DEFAULT_CACHE_DIR="./kiwi_boxes"
DEFAULT_REPO_URL="https://download.opensuse.org/distribution/leap/15.6/repo/oss"
DEFAULT_DESC_DIR="./image_description"

# Use environment variables if set, otherwise use defaults
ENGINE="${CONTAINER_ENGINE:-$DEFAULT_ENGINE}"
PROFILE="${KIWI_PROFILE:-$DEFAULT_PROFILE}"
BOX="${KIWI_BOX:-$DEFAULT_BOX}"
OUT_DIR="$DEFAULT_OUT_DIR"
CACHE_DIR="$DEFAULT_CACHE_DIR"
REPO_URL="$DEFAULT_REPO_URL"
DESC_DIR=""
DRY_RUN=false

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build an OpenSUSE Leap 15.6 image using the KIWI NG container.

Options:
  -e, --engine ENGINE       Container engine to use: 'docker' or 'podman' (default: $DEFAULT_ENGINE)
                            Can also be set via the CONTAINER_ENGINE environment variable.
  -p, --profile PROFILE     KIWI profile to build (default: $DEFAULT_PROFILE)
                            Can also be set via the KIWI_PROFILE environment variable.
  -b, --box BOX             KIWI box to build (default: $DEFAULT_BOX)
                            Can also be set via the KIWI_BOX environment variable.
  -o, --output-dir DIR      Directory where the built image will be saved (default: $DEFAULT_OUT_DIR)
  -c, --cache-dir DIR       Directory where the KIWI boxes are cached (default: $DEFAULT_CACHE_DIR)
  -d, --desc-dir DIR        Directory containing the KIWI image description.
                            (default: $DEFAULT_DESC_DIR)
  -r, --repo-url URL        URL of the OpenSUSE repository (default: $DEFAULT_REPO_URL)
  -n, --dry-run             Print the commands that would be executed without running them
  -h, --help                Show this help message and exit

Description:
  This script prepares target and cache directories with appropriate group write permissions,
  and executes the KIWI container ('dp.apps.rancher.io/containers/kiwi:10') with '--privileged'
  to build the OpenSUSE Leap 15.6 OS image based on a local image description.
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--engine)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            ENGINE="$2"
            shift 2
            ;;
        -p|--profile)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            PROFILE="$2"
            shift 2
            ;;
        -b|--box)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            BOX="$2"
            shift 2
            ;;
        -o|--output-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            OUT_DIR="$2"
            shift 2
            ;;
        -c|--cache-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            CACHE_DIR="$2"
            shift 2
            ;;
        -d|--desc-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            DESC_DIR="$2"
            shift 2
            ;;
        -r|--repo-url)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            REPO_URL="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            show_help >&2
            exit 1
            ;;
    esac
done

# Validate engine
if [[ "$ENGINE" != "docker" && "$ENGINE" != "podman" ]]; then
    echo "Error: Engine must be 'docker' or 'podman' (got: '$ENGINE')" >&2
    exit 1
fi

# Verify container engine is installed (skip check during dry-run to allow cross-environment testing)
if [ "$DRY_RUN" = false ]; then
    if ! command -v "$ENGINE" &> /dev/null; then
        echo "Error: Container engine '$ENGINE' is not installed or not in your PATH." >&2
        exit 1
    fi
fi

# Determine description directory
if [[ -z "$DESC_DIR" ]]; then
    DESC_DIR="$DEFAULT_DESC_DIR"
fi

# Verify description directory exists
if [ "$DRY_RUN" = false ] && [[ ! -d "$DESC_DIR" ]]; then
    echo "Error: Image description directory '$DESC_DIR' does not exist." >&2
    exit 1
fi

# Prepare target and cache directories
if [ "$DRY_RUN" = true ]; then
    echo "[Dry Run] Would create output directory: $OUT_DIR"
    echo "[Dry Run] Would create cache directory: $CACHE_DIR"
    echo "[Dry Run] Would apply group write permissions (chmod g+w)"
else
    echo "Preparing directories..."
    mkdir -p "$OUT_DIR"
    mkdir -p "$CACHE_DIR"
    chmod g+w "$OUT_DIR"
    chmod g+w "$CACHE_DIR"
fi

# Resolve absolute paths for volume mounting (mandatory for container runtimes)
# In dry-run we simulate resolution if directories don't physically exist yet
if [ "$DRY_RUN" = true ]; then
    # Simple mock or realpath if path exists
    ABS_DESC_DIR=$(mkdir -p "$DESC_DIR" &>/dev/null && realpath "$DESC_DIR" || echo "$(pwd)/${DESC_DIR#./}")
    ABS_OUT_DIR=$(mkdir -p "$OUT_DIR" &>/dev/null && realpath "$OUT_DIR" || echo "$(pwd)/${OUT_DIR#./}")
    ABS_CACHE_DIR=$(mkdir -p "$CACHE_DIR" &>/dev/null && realpath "$CACHE_DIR" || echo "$(pwd)/${CACHE_DIR#./}")
else
    ABS_DESC_DIR=$(realpath "$DESC_DIR")
    ABS_OUT_DIR=$(realpath "$OUT_DIR")
    ABS_CACHE_DIR=$(realpath "$CACHE_DIR")
fi

# Detect TTY availability
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Construct container build command
BUILD_CMD=(
    "$ENGINE" "run"
    "$TTY_FLAG"
    "--rm"
    "--privileged"
    "--volume" "$ABS_DESC_DIR:/image_description"
    "--volume" "$ABS_OUT_DIR:/target_image"
    "--volume" "$ABS_CACHE_DIR:/.kiwi_boxes"
    "dp.apps.rancher.io/containers/kiwi:10"
    "--debug"
    "--profile" "$PROFILE"
    "system" "boxbuild" "--box" "$BOX" "--"
    "--description" "/image_description"
    "--set-repo" "$REPO_URL"
    "--target-dir" "/target_image"
)

# Output summary of the planned operation
echo "=================================================="
echo "KIWI Build Configuration:"
echo "  Container Engine:  $ENGINE"
echo "  Profile:           $PROFILE"
echo "  KIWI Box:          $BOX"
echo "  Description Dir:   $ABS_DESC_DIR"
echo "  Output Dir:        $ABS_OUT_DIR"
echo "  Cache Dir:         $ABS_CACHE_DIR"
echo "  Repository URL:    $REPO_URL"
echo "=================================================="

if [ "$DRY_RUN" = true ]; then
    echo "Dry run enabled. The following command would be executed:"
    echo "--------------------------------------------------"
    echo "${BUILD_CMD[*]}"
    echo "--------------------------------------------------"
    exit 0
fi

# Execute the build
echo "Starting KIWI build via $ENGINE..."
if ! "${BUILD_CMD[@]}"; then
    echo "==================================================" >&2
    echo "Error: KIWI build failed!" >&2
    if [[ -f "$OUT_DIR/result.log" ]]; then
        echo "Last 10 lines from $OUT_DIR/result.log:" >&2
        echo "--------------------------------------------------" >&2
        tail -n 10 "$OUT_DIR/result.log" >&2
        echo "--------------------------------------------------" >&2
    fi
    echo "==================================================" >&2
    exit 1
fi
