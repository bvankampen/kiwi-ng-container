# OpenSUSE Leap 15.6 KIWI Builder

This project provides a highly robust, configurable, and automated shell script to build OpenSUSE Leap 15.6 operating system images using the KIWI NG container (`dp.apps.rancher.io/containers/kiwi:10`).

The build process is based on the reference guide from [SUSE Application Collection: KIWI NG](https://docs.apps.rancher.io/reference-guides/kiwi).

## Key Features

- **Configurable Container Engine:** Supports both **Docker** (default) and **Podman**.
- **Host Architecture Auto-Detection:** Automatically detects host architecture (`x86_64` vs `aarch64` / Apple Silicon) and sets target defaults accordingly.
- **Apple Silicon & ARM64 Support:** Out-of-the-box support for building and running `aarch64` images on M1/M2/M3 Macs with QEMU `virt` machine selection and automatic zstd EFI zboot kernel unpacking.
- **KVM & Acceleration Auto-Detection:** Auto-detects missing `/dev/kvm` (e.g. Docker Desktop on macOS) and safely configures `--no-accel` and CPU `--cpu max`.
- **Flexible CLI & Environment Variables:** Easily customize paths, repositories, machine types, and container engines via command-line flags or environment variables.
- **Dry Run Mode (`-n` / `--dry-run`):** Preview generated container commands and directory structures without pulling images or building.
- **Automated Directory & Permission Setup:** Creates required host directories and sets group write permissions (`chmod g+w`) necessary for container volume mounts.
- **Smart Path Resolution:** Resolves absolute host directory paths automatically for proper volume binding.
- **CI/CD & TTY Auto-Detection:** Dynamically switches between interactive (`-it`) and non-interactive (`-i`) container flags based on execution terminal context.
- **Multi-Profile Support:** Includes configurations for KVM/Xen, VMware, Cloud, Vagrant, Vagrant (Parallels), Hyper-V, and Raspberry Pi 4.
- **Integrated Test Suite:** Features a regression test runner (`test-build-image.sh`) for validating flag parsing, path resolution, and engine behavior.

---

## Directory Structure

```text
kiwi-ng-container/
├── build-image.sh          # Main KIWI build automation script
├── run-image.sh            # Standalone QEMU image runner script with Parallels ISO mounting
├── test-build-image.sh     # Automated unit/regression test suite
├── README.md               # Project documentation
├── image_description/      # KIWI image XML configuration definitions
│   ├── config.xml          # openSUSE Leap 15.6 image build specification
│   └── config.sh           # Post-install customization script (Vagrant/Parallels setup)
├── kiwi_boxes/             # Cache directory for KIWI box dependencies
├── parallels_iso/          # Directory to place Parallels Guest Tools ISOs
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
| `Vagrant` | `x86_64`, `aarch64` | Vagrant Box (`vagrant`) | XFS | GRUB2 (UEFI) |
| `Vagrant-parallels` | `x86_64`, `aarch64` | Vagrant Box (`vagrant`) | XFS | GRUB2 (UEFI) |
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
  -p, --profile PROFILE     KIWI profile to build (default: Vagrant)
                            Can also be set via the KIWI_PROFILE environment variable.
  -a, --target-arch ARCH    Target architecture: 'x86_64' or 'aarch64' (default: host architecture)
                            Can also be set via the KIWI_TARGET_ARCH environment variable.
  -m, --machine MACHINE     QEMU machine model (default: 'virt' for aarch64, none for x86_64)
                            Can also be set via the KIWI_MACHINE environment variable.
  --cpu CPU                 QEMU CPU model (default: 'max' when KVM is unavailable, 'host' otherwise)
                            Can also be set via the KIWI_CPU environment variable.
  --accel                   Enable KVM hardware acceleration
  --no-accel, --disable-kvm Disable KVM hardware acceleration (auto-detected if /dev/kvm is missing)
                            Can also be set via KIWI_ACCEL=true|false|auto (default: auto)
  -b, --box BOX             KIWI box to build (default: leap)
                            Can also be set via the KIWI_BOX environment variable.
  -l, --list-boxes          List all available build boxes and exit
  -o, --output-dir DIR      Directory where the built image will be saved (default: ./target_image)
  -c, --cache-dir DIR       Directory where the KIWI boxes are cached (default: ./kiwi_boxes)
  -d, --desc-dir DIR        Directory containing the KIWI image description.
                            (default: ./image_description)
  -s, --parallels-dir DIR   Directory containing Parallels Guest Tools ISO.
                            (default: ./parallels_iso)
  --with-parallels, --parallels
                            Enable Parallels Guest Tools installation and mount ISO dir
  --no-parallels, --without-parallels
                            Disable/skip Parallels Guest Tools installation
                            (Can also set WITH_PARALLELS=true|false|auto, default: auto)
  -r, --repo-url URL        URL of the OpenSUSE repository (default: https://download.opensuse.org/distribution/leap/15.6/repo/oss)
  -n, --dry-run             Print the commands that would be executed without running them
  -h, --help                Show this help message and exit
```

---

## Quick Start & Examples

### 1. Default Build (Docker with Vagrant Profile)
Build the OS image using Docker with the default `Vagrant` profile and default paths:
```bash
./build-image.sh
```

### 2. Selecting a Custom Build Profile (e.g. Vagrant-parallels, VMware, or kvm-and-xen)
Specify the profile via CLI option or environment variable:
```bash
# Build with Parallels Guest Tools (automatically selects prl-tools-lin-arm.iso on aarch64, or prl-tools-lin.iso on x86_64)
./build-image.sh -p Vagrant-parallels --with-parallels

# Build Vagrant-parallels profile without Parallels Guest Tools installation
./build-image.sh -p Vagrant-parallels --no-parallels

# Via CLI option for VMware
./build-image.sh -p VMware

# Via environment variable
KIWI_PROFILE=kvm-and-xen ./build-image.sh
```

### 3. Apple Silicon (M1/M2/M3) & Cross-Architecture Builds
The target architecture defaults to your host system architecture (`aarch64` on Apple Silicon). You can also explicitly specify `-a aarch64` or `-a x86_64`:
```bash
# Build Vagrant ARM64 box on Apple Silicon M1/M2/M3 Mac (automatically uses universal box, virt machine, and handles zstd kernel unpacking)
./build-image.sh -a aarch64

# Build Raspberry Pi 4 ARM64 image (automatically switches to aarch64 and universal box)
./build-image.sh -p RaspberryPi

# Explicitly build Cloud ARM64 image
./build-image.sh -p Cloud -a aarch64
```

### 4. Listing Available KIWI Build Boxes
List all pre-configured build boxes supported by the KIWI container:
```bash
./build-image.sh --list-boxes
```

### 5. Using Podman
Specify Podman via CLI flag or environment variable:
```bash
# Via CLI option
./build-image.sh -e podman

# Via environment variable
CONTAINER_ENGINE=podman ./build-image.sh
```

### 6. Dry Run Preview
Validate configuration and preview container invocation commands without executing:
```bash
./build-image.sh --dry-run
```

### 7. Custom Paths & Repository URL
```bash
./build-image.sh \
  --output-dir ./dist \
  --cache-dir ./cache \
  --desc-dir ./image_description \
  --repo-url https://download.opensuse.org/distribution/leap/15.6/repo/oss
```

---

## Booting & Running the OS Image (`run-image.sh`)

Once built, you can easily boot and test the generated OS image in QEMU via the standalone `./run-image.sh` runner script:

```bash
# Boot auto-detected OS image in ./target_image with Parallels ISO attached as CD-ROM
./run-image.sh

# Boot specific image file explicitly
./run-image.sh -i ./target_image/openSUSE-Leap-15.6-Minimal-VM.x86_64-15.6.0-0.qcow2

# Boot with custom RAM size (8GB) and Podman engine
./run-image.sh -e podman -m 8192

# Boot without attaching Parallels Guest Tools ISO
./run-image.sh --no-parallels
```

### Default System Credentials
- **Vagrant User:** `vagrant` / **Password:** `vagrant`
- **Root User:** `root` / **Password:** `linux`

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
