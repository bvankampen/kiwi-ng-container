#!/usr/bin/env bash

# build-image.sh - Build an OpenSUSE Leap 15.6 OS image using KIWI NG in a container.
# Configurable container engine (docker or podman).
# Sourced from reference guide: https://docs.apps.rancher.io/reference-guides/kiwi

set -euo pipefail

# Auto-detect default target architecture from host system
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    aarch64|arm64)
        DEFAULT_TARGET_ARCH="aarch64"
        ;;
    *)
        DEFAULT_TARGET_ARCH="x86_64"
        ;;
esac

# Default values
DEFAULT_ENGINE="docker"
DEFAULT_PROFILE="Vagrant"
DEFAULT_BOX="leap"
DEFAULT_MACHINE=""
DEFAULT_CPU=""
DEFAULT_ACCEL="auto"
DEFAULT_OUT_DIR="./target_image"
DEFAULT_CACHE_DIR="./kiwi_boxes"
DEFAULT_REPO_URL="https://download.opensuse.org/distribution/leap/15.6/repo/oss"
DEFAULT_DESC_DIR="./image_description"
DEFAULT_PARALLELS_DIR="./parallels_iso"
DEFAULT_WITH_PARALLELS="auto"

# Use environment variables if set, otherwise use defaults
ENGINE="${CONTAINER_ENGINE:-$DEFAULT_ENGINE}"
PROFILE="${KIWI_PROFILE:-$DEFAULT_PROFILE}"
BOX="${KIWI_BOX:-$DEFAULT_BOX}"
TARGET_ARCH="${KIWI_TARGET_ARCH:-$DEFAULT_TARGET_ARCH}"
MACHINE="${KIWI_MACHINE:-$DEFAULT_MACHINE}"
CPU="${KIWI_CPU:-$DEFAULT_CPU}"
ACCEL="${KIWI_ACCEL:-$DEFAULT_ACCEL}"
WITH_PARALLELS="${WITH_PARALLELS:-$DEFAULT_WITH_PARALLELS}"
OUT_DIR="$DEFAULT_OUT_DIR"
CACHE_DIR="$DEFAULT_CACHE_DIR"
REPO_URL="$DEFAULT_REPO_URL"
DESC_DIR=""
PARALLELS_DIR=""
EXPLICIT_BOX=false
EXPLICIT_ARCH=false
EXPLICIT_PROFILE=false
if [[ -n "${KIWI_PROFILE:-}" ]]; then
    EXPLICIT_PROFILE=true
fi
DRY_RUN=false
LIST_BOXES=false

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Build an OpenSUSE Leap 15.6 image using the KIWI NG container.

Options:
  -e, --engine ENGINE       Container engine to use: 'docker' or 'podman' (default: $DEFAULT_ENGINE)
                            Can also be set via the CONTAINER_ENGINE environment variable.
  -p, --profile PROFILE     KIWI profile to build (default: $DEFAULT_PROFILE)
                            Can also be set via the KIWI_PROFILE environment variable.
  -a, --target-arch ARCH    Target architecture: 'x86_64' or 'aarch64' (default: $DEFAULT_TARGET_ARCH)
                            Can also be set via the KIWI_TARGET_ARCH environment variable.
  -m, --machine MACHINE     QEMU machine model (default: 'virt' for aarch64, none for x86_64)
                            Can also be set via the KIWI_MACHINE environment variable.
  --cpu CPU                 QEMU CPU model (default: 'max' when KVM is unavailable, 'host' otherwise)
                            Can also be set via the KIWI_CPU environment variable.
  --accel                   Enable KVM hardware acceleration
  --no-accel, --disable-kvm Disable KVM hardware acceleration (auto-detected if /dev/kvm is missing)
                            Can also be set via KIWI_ACCEL=true|false|auto (default: $DEFAULT_ACCEL)
  -b, --box BOX             KIWI box to build (default: $DEFAULT_BOX)
                            Can also be set via the KIWI_BOX environment variable.
  -l, --list-boxes          List all available build boxes and exit
  -o, --output-dir DIR      Directory where the built image will be saved (default: $DEFAULT_OUT_DIR)
  -c, --cache-dir DIR       Directory where the KIWI boxes are cached (default: $DEFAULT_CACHE_DIR)
  -d, --desc-dir DIR        Directory containing the KIWI image description.
                            (default: $DEFAULT_DESC_DIR)
  -s, --parallels-dir DIR   Directory containing Parallels Guest Tools ISO.
                            (default: $DEFAULT_PARALLELS_DIR)
  --with-parallels, --parallels
                            Enable Parallels Guest Tools installation and mount ISO dir
  --no-parallels, --without-parallels
                            Disable/skip Parallels Guest Tools installation
                            (Can also set WITH_PARALLELS=true|false|auto, default: $DEFAULT_WITH_PARALLELS)
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
            EXPLICIT_PROFILE=true
            shift 2
            ;;
        -a|--target-arch)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            TARGET_ARCH="$2"
            EXPLICIT_ARCH=true
            shift 2
            ;;
        -m|--machine)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            MACHINE="$2"
            shift 2
            ;;
        --cpu)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            CPU="$2"
            shift 2
            ;;
        --accel)
            if [[ -n "${2:-}" && ! "$2" =~ ^- ]]; then
                ACCEL="$2"
                shift 2
            else
                ACCEL="true"
                shift
            fi
            ;;
        --no-accel|--disable-kvm)
            ACCEL="false"
            shift
            ;;
        -b|--box)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            BOX="$2"
            EXPLICIT_BOX=true
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
        -s|--parallels-dir)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            PARALLELS_DIR="$2"
            shift 2
            ;;
        --with-parallels|--parallels)
            WITH_PARALLELS="true"
            shift
            ;;
        --no-parallels|--without-parallels)
            WITH_PARALLELS="false"
            shift
            ;;
        -r|--repo-url)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Option '$1' requires an argument." >&2
                exit 1
            fi
            REPO_URL="$2"
            shift 2
            ;;
        -l|--list-boxes)
            LIST_BOXES=true
            shift
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

# Validate target architecture
if [[ "$TARGET_ARCH" != "x86_64" && "$TARGET_ARCH" != "aarch64" ]]; then
    echo "Error: Target architecture must be 'x86_64' or 'aarch64' (got: '$TARGET_ARCH')" >&2
    exit 1
fi

# Validate WITH_PARALLELS
if [[ "$WITH_PARALLELS" != "true" && "$WITH_PARALLELS" != "false" && "$WITH_PARALLELS" != "auto" ]]; then
    echo "Error: WITH_PARALLELS must be 'true', 'false', or 'auto' (got: '$WITH_PARALLELS')" >&2
    exit 1
fi

# Auto-detect target architecture for aarch64-only profiles if not explicitly set
if [ "$EXPLICIT_ARCH" = false ] && [[ -z "${KIWI_TARGET_ARCH:-}" ]]; then
    if [[ "$PROFILE" == "kvm" || "$PROFILE" == "RaspberryPi" ]]; then
        TARGET_ARCH="aarch64"
    fi
fi

# Switch default box to 'universal' when building aarch64 images (since 'leap' box is x86_64-only)
if [ "$TARGET_ARCH" = "aarch64" ] && [ "$EXPLICIT_BOX" = false ] && [[ -z "${KIWI_BOX:-}" ]]; then
    if [ "$BOX" = "leap" ]; then
        BOX="universal"
    fi
fi

# Default machine model to 'virt' for aarch64 if not explicitly specified
if [ "$TARGET_ARCH" = "aarch64" ] && [[ -z "$MACHINE" ]]; then
    MACHINE="virt"
fi

# Auto-detect acceleration availability
USE_ACCEL="kvm"
if [ "$ACCEL" = "false" ]; then
    USE_ACCEL="false"
elif [ "$ACCEL" = "hvf" ]; then
    USE_ACCEL="hvf"
elif [ "$ACCEL" = "auto" ]; then
    if [[ ! -c /dev/kvm ]]; then
        if [[ "$TARGET_ARCH" == "aarch64" ]]; then
            USE_ACCEL="hvf"
        else
            USE_ACCEL="false"
        fi
    fi
fi

# Default CPU model to 'max' when acceleration is disabled and no CPU model was explicitly specified
if [ "$USE_ACCEL" = "false" ] && [[ -z "$CPU" ]]; then
    CPU="max"
fi

# Verify container engine is installed (skip check during dry-run to allow cross-environment testing)
if [ "$DRY_RUN" = false ]; then
    if ! command -v "$ENGINE" &> /dev/null; then
        echo "Error: Container engine '$ENGINE' is not installed or not in your PATH." >&2
        exit 1
    fi
fi

# Handle listing available boxes
if [ "$LIST_BOXES" = true ]; then
    if [ "$DRY_RUN" = true ]; then
        echo "[Dry Run] Would execute: $ENGINE run -i --rm dp.apps.rancher.io/containers/kiwi:10 system boxbuild --list-boxes"
        exit 0
    fi
    "$ENGINE" run -i --rm dp.apps.rancher.io/containers/kiwi:10 system boxbuild --list-boxes | awk '
BEGIN {
    print "Available KIWI Boxes:"
}
/^\[/ { next }
/^- arch:/ {
    if (box != "") {
        printf "  - %-12s (%s)\n", box, archs
    }
    box = ""
    archs = ""
    next
}
/^    name: / {
    arch = $2
    if (archs == "") {
        archs = arch
    } else {
        archs = archs ", " arch
    }
}
/^  name: / {
    box = $2
}
END {
    if (box != "") {
        printf "  - %-12s (%s)\n", box, archs
    }
}
'
    exit 0
fi

# Determine description and parallels directories
if [[ -z "$DESC_DIR" ]]; then
    DESC_DIR="$DEFAULT_DESC_DIR"
fi

if [[ -z "$PARALLELS_DIR" ]]; then
    PARALLELS_DIR="$DEFAULT_PARALLELS_DIR"
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
    ABS_PARALLELS_DIR=$(mkdir -p "$PARALLELS_DIR" &>/dev/null && realpath "$PARALLELS_DIR" || echo "$(pwd)/${PARALLELS_DIR#./}")
else
    ABS_DESC_DIR=$(realpath "$DESC_DIR")
    ABS_OUT_DIR=$(realpath "$OUT_DIR")
    ABS_CACHE_DIR=$(realpath "$CACHE_DIR")
    if [[ -d "$PARALLELS_DIR" ]]; then
        ABS_PARALLELS_DIR=$(realpath "$PARALLELS_DIR")
    else
        ABS_PARALLELS_DIR=""
    fi
fi

# Determine whether to enable Parallels Guest Tools installation (only supported for Vagrant/Vagrant-parallels)
MOUNT_PARALLELS=false
if [[ "$PROFILE" == "Vagrant" || "$PROFILE" == "Vagrant-parallels" ]]; then
    if [ "$WITH_PARALLELS" = "true" ]; then
        MOUNT_PARALLELS=true
    elif [ "$WITH_PARALLELS" = "auto" ]; then
        if [[ "$PROFILE" =~ [Pp]arallels ]]; then
            MOUNT_PARALLELS=true
        elif [[ -n "$ABS_PARALLELS_DIR" && -d "$ABS_PARALLELS_DIR" ]]; then
            if find "$ABS_PARALLELS_DIR" -maxdepth 1 -name "*.iso" -print -quit 2>/dev/null | grep -q .; then
                MOUNT_PARALLELS=true
            fi
        fi
    fi
elif [ "$WITH_PARALLELS" = "true" ] && [ "$DRY_RUN" = false ]; then
    echo "Warning: Parallels tools are only supported for 'Vagrant' or 'Vagrant-parallels' profiles. Skipping mount for profile '$PROFILE'." >&2
fi

# Auto-switch default Vagrant profile to Vagrant-parallels when Parallels Tools mount is active
if [ "$MOUNT_PARALLELS" = true ] && [ "$EXPLICIT_PROFILE" = false ]; then
    if [ "$PROFILE" = "Vagrant" ]; then
        PROFILE="Vagrant-parallels"
    fi
fi

# Detect TTY availability
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Helper function to unpack EFI zboot images in cache directory if needed
unpack_cache_zboot_kernels() {
    local cache_dir="$1"
    if command -v python3 &>/dev/null && [[ -d "$cache_dir" ]]; then
        python3 - "$cache_dir" << 'EOF'
import os, sys, struct, ctypes

cache_dir = sys.argv[1]
for root, dirs, files in os.walk(cache_dir):
    for file in files:
        if file.startswith('kernel.'):
            kernel_path = os.path.join(root, file)
            try:
                with open(kernel_path, 'rb') as f:
                    data = f.read()
                if data[:2] == b'MZ' and b'zimg' in data[:32]:
                    start_off = struct.unpack('<I', data[8:12])[0]
                    payload_size = struct.unpack('<I', data[12:16])[0]
                    comp_type = data[24:32].rstrip(b'\x00')
                    decomp = None
                    if comp_type == b'zstd':
                        payload = data[start_off:start_off + payload_size]
                        for libname in ['libzstd.so.1', 'libzstd.so', 'libzstd.dylib', 'libzstd.1.dylib']:
                            try:
                                libzstd = ctypes.CDLL(libname)
                                break
                            except Exception:
                                libzstd = None
                        if libzstd:
                            libzstd.ZSTD_decompress.argtypes = [
                                ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t
                            ]
                            libzstd.ZSTD_decompress.restype = ctypes.c_size_t
                            libzstd.ZSTD_isError.argtypes = [ctypes.c_size_t]
                            libzstd.ZSTD_isError.restype = ctypes.c_uint
                            out_capacity = 256 * 1024 * 1024
                            out_buf = ctypes.create_string_buffer(out_capacity)
                            res = libzstd.ZSTD_decompress(out_buf, out_capacity, payload, len(payload))
                            if not libzstd.ZSTD_isError(res):
                                decomp = out_buf.raw[:res]
                    elif comp_type in (b'gzip', b'gz'):
                        import gzip
                        decomp = gzip.decompress(data[start_off:start_off + payload_size])
                    elif comp_type in (b'xz', b'lzma'):
                        import lzma
                        decomp = lzma.decompress(data[start_off:start_off + payload_size])
                    elif comp_type in (b'bz2', b'bzip2'):
                        import bz2
                        decomp = bz2.decompress(data[start_off:start_off + payload_size])

                    if decomp:
                        print(f"Unpacked EFI zboot kernel: {kernel_path}")
                        with open(kernel_path, 'wb') as out_f:
                            out_f.write(decomp)
            except Exception:
                pass
EOF
    fi
}

# Construct container build command
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX_DOWNLOAD_PATCH="$SCRIPT_DIR/scripts/box_download.py"
BOX_BUILD_PATCH="$SCRIPT_DIR/scripts/box_build.py"

BUILD_CMD=(
    "$ENGINE" "run"
    "$TTY_FLAG"
    "--rm"
    "--privileged"
    "--volume" "$ABS_DESC_DIR:/image_description"
    "--volume" "$ABS_OUT_DIR:/target_image"
    "--volume" "$ABS_CACHE_DIR:/.kiwi_boxes"
)

if [[ -f "$BOX_DOWNLOAD_PATCH" ]]; then
    ABS_BOX_DOWNLOAD_PATCH=$(realpath "$BOX_DOWNLOAD_PATCH")
    BUILD_CMD+=("--volume" "$ABS_BOX_DOWNLOAD_PATCH:/usr/lib/python3.11/site-packages/kiwi_boxed_plugin/box_download.py")
fi

if [[ -f "$BOX_BUILD_PATCH" ]]; then
    ABS_BOX_BUILD_PATCH=$(realpath "$BOX_BUILD_PATCH")
    BUILD_CMD+=("--volume" "$ABS_BOX_BUILD_PATCH:/usr/lib/python3.11/site-packages/kiwi_boxed_plugin/box_build.py")
fi

# If parallels tools are enabled and directory exists, bind mount it into description overlay
if [ "$MOUNT_PARALLELS" = true ]; then
    if [[ -n "$ABS_PARALLELS_DIR" && -d "$ABS_PARALLELS_DIR" ]]; then
        BUILD_CMD+=("--volume" "$ABS_PARALLELS_DIR:/image_description/root/tmp/parallels_iso")
    elif [ "$DRY_RUN" = false ]; then
        echo "Warning: Parallels tools explicitly enabled, but directory '$PARALLELS_DIR' does not exist." >&2
    fi
fi

BUILD_CMD+=(
    "dp.apps.rancher.io/containers/kiwi:10"
    "--debug"
    "--profile" "$PROFILE"
    "system" "boxbuild" "--box" "$BOX" "--$TARGET_ARCH"
)

if [[ -n "$MACHINE" ]]; then
    BUILD_CMD+=("--machine" "$MACHINE")
fi

if [[ -n "$CPU" ]]; then
    BUILD_CMD+=("--cpu" "$CPU")
fi

if [ "$USE_ACCEL" = false ]; then
    BUILD_CMD+=("--no-accel")
fi

BUILD_CMD+=(
    "--"
    "--description" "/image_description"
    "--set-repo" "$REPO_URL"
    "--target-dir" "/target_image"
)

# Output summary of the planned operation
echo "=================================================="
echo "KIWI Build Configuration:"
echo "  Container Engine:  $ENGINE"
echo "  Profile:           $PROFILE"
echo "  Target Arch:       $TARGET_ARCH"
if [[ -n "$MACHINE" ]]; then
echo "  QEMU Machine:      $MACHINE"
fi
if [[ -n "$CPU" ]]; then
echo "  QEMU CPU:          $CPU"
fi
echo "  KVM Acceleration:  $USE_ACCEL"
echo "  KIWI Box:          $BOX"
echo "  Parallels Tools:   $WITH_PARALLELS (active: $MOUNT_PARALLELS)"
echo "  Description Dir:   $ABS_DESC_DIR"
echo "  Output Dir:        $ABS_OUT_DIR"
echo "  Cache Dir:         $ABS_CACHE_DIR"
if [[ -n "$ABS_PARALLELS_DIR" ]]; then
echo "  Parallels Dir:     $ABS_PARALLELS_DIR"
fi
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
echo "Preparing KIWI box kernels..."
unpack_cache_zboot_kernels "$ABS_CACHE_DIR"

echo "Starting KIWI build via $ENGINE..."
BUILD_STATUS=0
if ! "${BUILD_CMD[@]}"; then
    BUILD_STATUS=$?
fi

# Archive log to a unique file to prevent subsequent builds from overwriting it
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
UNIQUE_LOG="result-${PROFILE}-${TARGET_ARCH}-${TIMESTAMP}.log"

if [[ -f "$OUT_DIR/result.log" ]]; then
    mv "$OUT_DIR/result.log" "$OUT_DIR/$UNIQUE_LOG"
    echo "Build log saved to: $OUT_DIR/$UNIQUE_LOG"
fi

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "==================================================" >&2
    echo "Error: KIWI build failed!" >&2
    if [[ -f "$OUT_DIR/$UNIQUE_LOG" ]]; then
        echo "Last 10 lines from $OUT_DIR/$UNIQUE_LOG:" >&2
        echo "--------------------------------------------------" >&2
        tail -n 10 "$OUT_DIR/$UNIQUE_LOG" >&2
        echo "--------------------------------------------------" >&2
    fi
    echo "==================================================" >&2
    exit "$BUILD_STATUS"
fi
