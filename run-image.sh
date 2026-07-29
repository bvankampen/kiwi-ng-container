#!/usr/bin/env bash

# run-image.sh - Boot and run built OS images in QEMU using KIWI container runtime
# Sourced from reference guide: https://docs.apps.rancher.io/reference-guides/kiwi

set -euo pipefail

# Auto-detect default architecture from host system
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    aarch64|arm64)
        DEFAULT_ARCH="aarch64"
        ;;
    *)
        DEFAULT_ARCH="x86_64"
        ;;
esac

# Default values
DEFAULT_ENGINE="docker"
DEFAULT_MEMORY="4096"
DEFAULT_MACHINE=""
DEFAULT_TARGET_DIR="./target_image"
DEFAULT_PARALLELS_DIR="./parallels_iso"
DEFAULT_SSH_PORT="2222"
DEFAULT_WITH_PARALLELS="auto"

ENGINE="${CONTAINER_ENGINE:-$DEFAULT_ENGINE}"
MEMORY="$DEFAULT_MEMORY"
ARCH="${KIWI_TARGET_ARCH:-$DEFAULT_ARCH}"
MACHINE="${KIWI_MACHINE:-$DEFAULT_MACHINE}"
TARGET_DIR="$DEFAULT_TARGET_DIR"
PARALLELS_DIR="$DEFAULT_PARALLELS_DIR"
SSH_PORT="$DEFAULT_SSH_PORT"
WITH_PARALLELS="$DEFAULT_WITH_PARALLELS"
IMAGE_FILE=""
PARALLELS_ISO=""
DRY_RUN=false

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Boot and run a built OpenSUSE Leap 15.6 image using QEMU inside the KIWI container runtime.

Options:
  -i, --image FILE          Path to OS image file (.qcow2, .raw, .vmdk, .vhdx).
                            (default: auto-detected in $DEFAULT_TARGET_DIR)
  -s, --parallels-iso FILE  Path to Parallels Guest Tools ISO file.
                            (default: auto-detected in $DEFAULT_PARALLELS_DIR)
  --with-parallels          Attach Parallels Guest Tools ISO as CD-ROM drive
  --no-parallels            Do not attach Parallels Guest Tools ISO
  -e, --engine ENGINE       Container engine to use: 'docker' or 'podman' (default: $DEFAULT_ENGINE)
                            Can also be set via CONTAINER_ENGINE environment variable.
  -a, --arch ARCH           System architecture: 'x86_64' or 'aarch64' (default: $DEFAULT_ARCH)
  -M, --machine MACHINE     QEMU machine model (default: 'virt' for aarch64, none for x86_64)
  -m, --memory MEM          RAM allocation in MB (default: $DEFAULT_MEMORY)
  -p, --ssh-port PORT       Host port forwarded to SSH port 22 in VM (default: $DEFAULT_SSH_PORT)
  -n, --dry-run             Print the container command without executing
  -h, --help                Show this help message and exit

Examples:
  # Boot default image auto-detected in ./target_image
  ./run-image.sh

  # Boot a specific qcow2 image with Parallels ISO attached
  ./run-image.sh -i ./target_image/openSUSE-Leap-15.6-Minimal-VM.x86_64-15.6.0-0.qcow2 --with-parallels

  # Boot with Podman and 8GB RAM
  ./run-image.sh -e podman -m 8192
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            IMAGE_FILE="$2"
            shift 2
            ;;
        -s|--parallels-iso)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            PARALLELS_ISO="$2"
            shift 2
            ;;
        --with-parallels)
            WITH_PARALLELS="true"
            shift
            ;;
        --no-parallels)
            WITH_PARALLELS="false"
            shift
            ;;
        -e|--engine)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            ENGINE="$2"
            shift 2
            ;;
        -a|--arch)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            ARCH="$2"
            shift 2
            ;;
        -M|--machine)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            MACHINE="$2"
            shift 2
            ;;
        -m|--memory)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            MEMORY="$2"
            shift 2
            ;;
        -p|--ssh-port)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            SSH_PORT="$2"
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

# Validate architecture
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
    echo "Error: Architecture must be 'x86_64' or 'aarch64' (got: '$ARCH')" >&2
    exit 1
fi

# Verify container engine is installed
if [ "$DRY_RUN" = false ]; then
    if ! command -v "$ENGINE" &> /dev/null; then
        echo "Error: Container engine '$ENGINE' is not installed or not in PATH." >&2
        exit 1
    fi
fi

# Auto-detect image file if not specified
if [[ -z "$IMAGE_FILE" ]]; then
    if [[ -d "$TARGET_DIR" ]]; then
        # Search for .qcow2, .raw, .vmdk, .vhdx
        FOUND_IMAGE=$(find "$TARGET_DIR" -maxdepth 1 \( -name "*.qcow2" -o -name "*.raw" -o -name "*.vmdk" -o -name "*.vhdx" \) 2>/dev/null | head -n 1 || true)
        if [[ -n "$FOUND_IMAGE" ]]; then
            IMAGE_FILE="$FOUND_IMAGE"
        fi
    fi
fi

if [[ -z "$IMAGE_FILE" ]]; then
    if [ "$DRY_RUN" = true ]; then
        IMAGE_FILE="$TARGET_DIR/openSUSE-Leap-15.6-Minimal.x86_64.qcow2"
    else
        echo "Error: No OS image file found in '$TARGET_DIR'. Specify one with -i/--image." >&2
        exit 1
    fi
fi

# Verify image file exists
if [ "$DRY_RUN" = false ] && [[ ! -f "$IMAGE_FILE" ]]; then
    echo "Error: Specified image file '$IMAGE_FILE' does not exist." >&2
    exit 1
fi

# Determine image format for QEMU drive
FORMAT="qcow2"
case "$IMAGE_FILE" in
    *.raw)  FORMAT="raw" ;;
    *.vmdk) FORMAT="vmdk" ;;
    *.vhdx) FORMAT="vhdx" ;;
    *)      FORMAT="qcow2" ;;
esac

# Auto-detect Parallels ISO if not explicitly specified
if [[ -z "$PARALLELS_ISO" ]]; then
    if [[ -d "$PARALLELS_DIR" ]]; then
        if [[ "$ARCH" == "aarch64" && -f "$PARALLELS_DIR/prl-tools-lin-arm.iso" ]]; then
            PARALLELS_ISO="$PARALLELS_DIR/prl-tools-lin-arm.iso"
        elif [ -f "$PARALLELS_DIR/prl-tools-lin.iso" ]; then
            PARALLELS_ISO="$PARALLELS_DIR/prl-tools-lin.iso"
        else
            PARALLELS_ISO=$(find "$PARALLELS_DIR" -maxdepth 1 -name "*.iso" 2>/dev/null | head -n 1 || true)
        fi
    fi
fi

# Resolve whether to mount Parallels ISO
ATTACH_PARALLELS=false
if [ "$WITH_PARALLELS" = "true" ]; then
    ATTACH_PARALLELS=true
elif [ "$WITH_PARALLELS" = "auto" ]; then
    if [[ -n "$PARALLELS_ISO" && -f "$PARALLELS_ISO" ]]; then
        ATTACH_PARALLELS=true
    fi
fi

# Resolve absolute paths
ABS_IMAGE_PATH=$(mkdir -p "$(dirname "$IMAGE_FILE")" &>/dev/null && realpath "$IMAGE_FILE" 2>/dev/null || echo "$(pwd)/${IMAGE_FILE#./}")
ABS_IMAGE_DIR=$(dirname "$ABS_IMAGE_PATH")
IMAGE_FILENAME=$(basename "$ABS_IMAGE_PATH")

ABS_PARALLELS_ISO=""
PARALLELS_ISO_FILENAME=""
if [ "$ATTACH_PARALLELS" = true ] && [[ -n "$PARALLELS_ISO" ]]; then
    if [ "$DRY_RUN" = true ] || [[ -f "$PARALLELS_ISO" ]]; then
        ABS_PARALLELS_ISO=$(mkdir -p "$(dirname "$PARALLELS_ISO")" &>/dev/null && realpath "$PARALLELS_ISO" 2>/dev/null || echo "$(pwd)/${PARALLELS_ISO#./}")
        ABS_PARALLELS_DIR=$(dirname "$ABS_PARALLELS_ISO")
        PARALLELS_ISO_FILENAME=$(basename "$ABS_PARALLELS_ISO")
    else
        echo "Warning: Parallels ISO requested but '$PARALLELS_ISO' not found. Skipping ISO mount." >&2
        ATTACH_PARALLELS=false
    fi
fi

# Detect TTY availability
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Entrypoint QEMU executable and machine setup
QEMU_EXEC="qemu-system-x86_64"
ACCEL=""
if [[ "$ARCH" == "aarch64" ]]; then
    QEMU_EXEC="qemu-system-aarch64"
    if [[ -z "$MACHINE" ]]; then
        MACHINE="virt"
    fi
    if [[ ! -c /dev/kvm ]]; then
        ACCEL="hvf"
    else
        ACCEL="kvm"
    fi
fi

# Construct container command
RUN_CMD=(
    "$ENGINE" "run"
    "$TTY_FLAG"
    "--rm"
    "--volume" "$ABS_IMAGE_DIR:/target_image"
)

if [ "$ATTACH_PARALLELS" = true ] && [[ -n "$ABS_PARALLELS_ISO" ]]; then
    RUN_CMD+=("--volume" "$ABS_PARALLELS_DIR:/parallels_iso")
fi

RUN_CMD+=(
    "--entrypoint" "$QEMU_EXEC"
    "dp.apps.rancher.io/containers/kiwi:10"
    "-m" "$MEMORY"
    "-smp" "2"
)

if [[ -n "$MACHINE" ]]; then
    RUN_CMD+=("-machine" "$MACHINE")
fi

if [[ -n "$ACCEL" ]]; then
    RUN_CMD+=("-accel" "accel=$ACCEL")
fi

if [[ "$ARCH" == "aarch64" ]]; then
    RUN_CMD+=("-cpu" "max")
fi

RUN_CMD+=(
    "-boot" "c"
    "-drive" "file=/target_image/$IMAGE_FILENAME,format=$FORMAT,if=virtio"
    "-net" "nic,model=virtio"
    "-net" "user,hostfwd=tcp::$SSH_PORT-:22"
    "-serial" "stdio"
)

if [ "$ATTACH_PARALLELS" = true ] && [[ -n "$PARALLELS_ISO_FILENAME" ]]; then
    RUN_CMD+=("-drive" "file=/parallels_iso/$PARALLELS_ISO_FILENAME,media=cdrom")
fi

echo "=================================================="
echo "QEMU OS Image Runner Configuration:"
echo "  Container Engine:  $ENGINE"
echo "  Architecture:      $ARCH"
if [[ -n "$MACHINE" ]]; then
echo "  QEMU Machine:      $MACHINE"
fi
if [[ -n "$ACCEL" ]]; then
echo "  QEMU Acceleration: $ACCEL"
fi
echo "  Memory:            ${MEMORY}MB"
echo "  Image File:        $ABS_IMAGE_PATH"
if [ "$ATTACH_PARALLELS" = true ]; then
echo "  Parallels ISO:     $ABS_PARALLELS_ISO"
else
echo "  Parallels ISO:     Disabled/Not attached"
fi
echo "  Forwarded SSH Port: $SSH_PORT -> 22"
echo "=================================================="

if [ "$DRY_RUN" = true ]; then
    echo "Dry run enabled. The following command would be executed:"
    echo "--------------------------------------------------"
    echo "${RUN_CMD[*]}"
    echo "--------------------------------------------------"
    exit 0
fi

echo "Starting QEMU VM (Default root password: linux or vagrant)..."
echo "Press Ctrl+C to stop the virtual machine."
echo "--------------------------------------------------"
"${RUN_CMD[@]}"
