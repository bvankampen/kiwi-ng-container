# OpenSUSE Leap 15.6 KIWI Builder

This project provides a highly robust, configurable, and automated shell script to build OpenSUSE Leap 15.6 operating system images using the KIWI NG container (`dp.apps.rancher.io/containers/kiwi:10`).

The build process is based on the reference guide from [SUSE Application Collection: KIWI NG](https://docs.apps.rancher.io/reference-guides/kiwi).

## Key Features

- **Configurable Container Engine:** Supports both **Docker** (default) and **Podman**.
- **Flexible CLI & Environment Variables:** Easily customize paths, repositories, and container engines via command-line flags or environment variables.
- **Dry Run Mode (`-n` / `--dry-run`):** Preview generated container commands and directory structures without pulling images or building.
- **Automated Directory & Permission Setup:** Creates required host directories and sets group write permissions (`chmod g+w`) necessary for container volume mounts.
- **Smart Path Resolution:** Resolves absolute host directory paths automatically for proper volume binding.
- **CI/CD & TTY Auto-Detection:** Dynamically switches between interactive (`-it`) and non-interactive (`-i`) container flags based on execution terminal context.
- **Multi-Profile Support:** Includes configurations for KVM/Xen, VMware, Cloud, Hyper-V, and Raspberry Pi 4.
- **Integrated Test Suite:** Features a regression test runner (`test-build-image.sh`) for validating flag parsing, path resolution, and engine behavior.

---

## Directory Structure

```text
kiwi-ng-container/
├── build-image.sh          # Main KIWI build automation script
├── test-build-image.sh     # Automated unit/regression test suite
├── README.md               # Project documentation
├── image_description/      # KIWI image XML configuration definitions
│   └── config.xml          # openSUSE Leap 15.6 image build specification
├── kiwi_boxes/             # Cache directory for KIWI box dependencies
└── target_image/           # Output directory for generated OS images and logs
```

---

## Prerequisites

- **Container Engine:** [Docker](https://www.docker.com/) or [Podman](https://podman.io/) installed and accessible in `PATH`.
- **System Privileges:** Container execution requires `--privileged` access for KIWI disk image creation.
- **Disk Space:** At least 10–20 GB of free space recommended for target builds and caching.

---

## Supported Build Profiles

The included `image_description/config.xml` provides build targets for various hypervisors and architectures:

| Profile | Target Architecture | Image Format | File System | Bootloader / Firmware |
| :--- | :--- | :--- | :--- | :--- |
| `kvm-and-xen` | `x86_64` | QCOW2 (`qcow2`) | Btrfs | GRUB2 (UEFI) |
| `kvm` | `aarch64` | QCOW2 (`qcow2`) | Btrfs | GRUB2 (UEFI) |
| `VMware` | `x86_64` | VMDK (`vmdk`) | Btrfs | GRUB2 (UEFI) |
| `Cloud` | `x86_64`, `aarch64` | QCOW2 (`qcow2`) | XFS | GRUB2 (UEFI) |
| `MS-HyperV` | `x86_64`, `aarch64` | VHDX (`vhdx`) | Btrfs | GRUB2 (UEFI) |
| `RaspberryPi` | `aarch64` | OEM raw image | Btrfs | GRUB2 / EFI (`dracut`) |

---

## Usage Guide & Options

```text
Usage: build-image.sh [OPTIONS]

Build an OpenSUSE Leap 15.6 image using the KIWI NG container.

Options:
  -e, --engine ENGINE       Container engine to use: 'docker' or 'podman' (default: docker)
                            Can also be set via the CONTAINER_ENGINE environment variable.
  -p, --profile PROFILE     KIWI profile to build (default: Cloud)
                            Can also be set via the KIWI_PROFILE environment variable.
  -b, --box BOX             KIWI box to build (default: leap)
                            Can also be set via the KIWI_BOX environment variable.
  -l, --list-boxes          List all available build boxes and exit
  -o, --output-dir DIR      Directory where the built image will be saved (default: ./target_image)
  -c, --cache-dir DIR       Directory where the KIWI boxes are cached (default: ./kiwi_boxes)
  -d, --desc-dir DIR        Directory containing the KIWI image description (default: ./image_description)
  -r, --repo-url URL        URL of the OpenSUSE repository (default: https://download.opensuse.org/distribution/leap/15.6/repo/oss)
  -n, --dry-run             Print the commands that would be executed without running them
  -h, --help                Show this help message and exit
```

---

## Quick Start & Examples

### 1. Default Build (Docker with Cloud Profile)
Build the OS image using Docker with the default `Cloud` profile and default paths:
```bash
./build-image.sh
```

### 2. Selecting a Custom Build Profile (e.g. VMware or kvm-and-xen)
Specify the profile via CLI option or environment variable:
```bash
# Via CLI option
./build-image.sh -p VMware

# Via environment variable
KIWI_PROFILE=kvm-and-xen ./build-image.sh
```

### 3. Listing Available KIWI Build Boxes
List all pre-configured build boxes supported by the KIWI container:
```bash
./build-image.sh --list-boxes
```

### 4. Using Podman
Specify Podman via CLI flag or environment variable:
```bash
# Via CLI option
./build-image.sh -e podman

# Via environment variable
CONTAINER_ENGINE=podman ./build-image.sh
```

### 5. Dry Run Preview
Validate configuration and preview container invocation commands without executing:
```bash
./build-image.sh --dry-run
```

### 4. Custom Paths & Repository URL
```bash
./build-image.sh \
  --output-dir ./dist \
  --cache-dir ./cache \
  --desc-dir ./image_description \
  --repo-url https://download.opensuse.org/distribution/leap/15.6/repo/oss
```

---

## Booting the Built OS Image (Example)

Once built, you can boot and test the generated OS image inside QEMU using the KIWI NG container (example for default `Cloud` profile image):

```bash
docker run -it --rm \
  --volume "$(pwd)/target_image:/target_image" \
  --entrypoint qemu-system-x86_64 \
  dp.apps.rancher.io/containers/kiwi:10 \
  -boot c \
  -drive file=/target_image/openSUSE-Leap-15.6-Minimal-VM.x86_64-15.6.0-0.qcow2,format=qcow2,if=virtio \
  -m 4096 \
  -serial stdio
```

### Default System Credentials
- **Username:** `root`
- **Password:** `linux`

---

## Running the Automated Test Suite

Run the regression test suite to verify CLI option parsing, path resolution, environment variable handling, and dry-run output:

```bash
./test-build-image.sh
```

---

## References & Documentation

- **KIWI Container Reference Guide:** [https://docs.apps.rancher.io/reference-guides/kiwi](https://docs.apps.rancher.io/reference-guides/kiwi)
- **KIWI NG Official Documentation:** [https://osinside.github.io/kiwi](https://osinside.github.io/kiwi)
