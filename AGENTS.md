# AGENTS.md

## Repository Overview & Philosophy
This repository contains a container-based build environment for creating OpenSUSE Leap 15.6 OS images using KIWI NG (`dp.apps.rancher.io/containers/kiwi:10`). It is engineered for seamless cross-platform support across `x86_64` and `aarch64` hosts (including Apple Silicon M1/M2/M3 Macs) using Docker or Podman.

Key goals for all modifications:
1. **Cross-Architecture Portability:** First-class support for both `x86_64` and `aarch64` architectures.
2. **Terminal Safety:** Smart TTY handling (`-it` vs `-i`) for interactive shells vs CI/CD pipelines.
3. **Zero-Assumption Scripting:** Absolute path resolution, directory pre-creation, permission handling (`chmod g+w`), and explicit flag propagation.
4. **Comprehensive Test Coverage:** Automated regression suite via `test-build-image.sh`.

---

## Codebase Structure

- **`build-image.sh`**: Primary entry point script for building OS images using KIWI NG inside a container. Handles host auto-detection, path resolution, container engine selection, mount configuration, and execution.
- **`run-image.sh`**: Standalone helper script to boot generated QEMU disk images (`qcow2`, `raw`, etc.) directly with optional Parallels ISO CD-ROM mounts.
- **`test-build-image.sh`**: Automated regression test suite containing 30+ tests validating CLI flag parsing, environment variables, target architecture auto-detection, and dry-run output formatting.
- **`image_description/`**:
  - `config.xml`: KIWI XML image definition file specifying build profiles (`Vagrant`, `Vagrant-parallels`, `kvm-and-xen`, `RaspberryPi`, `Cloud`, etc.), base packages, repository definitions, and image types.
  - `config.sh`: Post-installation customization script executed inside the target chroot during image build.
- **`scripts/`**: Python container overlays mounted into `/usr/lib/python3.11/site-packages/kiwi_boxed_plugin/` inside the KIWI container:
  - `box_build.py`: Patches `BoxBuild.run()` to support custom QEMU machine types (`-machine virt`), CPU types, and acceleration configuration.
  - `box_download.py`: Patches `_extract_kernel_from_tarball()` to automatically decompress zstd-compressed EFI zboot Linux kernels (common in openSUSE Leap 15.6 ARM64 box downloads).
- **`parallels_iso/`**: Directory for Parallels Guest Tools ISOs (`prl-tools-lin.iso` for x86_64, `prl-tools-lin-arm.iso` for ARM64).
- **`kiwi_boxes/`**: Cached KIWI build box dependencies (e.g. `universal`, `leap`, `tumbleweed`).
- **`target_image/`**: Destination directory for generated OS images, checksums, logs, and build artifacts.

---

## Architectural Conventions & Fixes

1. **Host Architecture Auto-Detection**:
   - `build-image.sh` and `run-image.sh` auto-detect system architecture via `uname -m`. `arm64` or `aarch64` sets target defaults to `aarch64` and selects the `tumbleweed` KIWI box. `x86_64` defaults to `leap`.
2. **QEMU Machine Selection**:
   - `aarch64` target requires `-machine virt` for QEMU execution inside `boxbuild`. `build-image.sh` automatically passes `-machine virt` when target architecture is `aarch64`.
3. **zstd EFI zboot Kernel Unpacking**:
   - OpenSUSE Leap 15.6 ARM64 kernel binaries in build boxes are compressed EFI zboot binaries. `scripts/box_download.py` inspects kernel headers and decompresses zstd payloads using `libzstd.so.1` ctypes interface.
4. **macOS / Docker Desktop Acceleration**:
   - When `/dev/kvm` is missing on macOS ARM64 hosts, `scripts/box_build.py` and `build-image.sh` default to `--no-accel` with CPU type `--cpu max` (since `hvf` is currently unstable/unsupported in QEMU container builds).
5. **GPG Signing Keys & Bootstrap Phase**:
   - `openSUSE-build-key` is included in `<packages type="bootstrap">` in `config.xml` to prevent `NOKEY` RPM signature verification failures during early chroot creation.
   - Repositories set `package_gpgcheck="false"` and `--set-repo` parameters include `$REPO_URL,rpm-md,repo,1,true,false` for reliable package downloads during build-time.

---

## Development & Testing Workflow

### 1. Running Regression Tests
Whenever modifying `build-image.sh`, `run-image.sh`, or configuration defaults:
```bash
./test-build-image.sh
```
All tests must pass cleanly before committing changes.

### 2. Adding New Tests
When adding new CLI options or environment variables, add matching test cases to `test-build-image.sh`. Use `assert_contains` and `assert_not_contains` against `DRY_RUN` outputs.

### 3. Dry-Run Verification
Always verify CLI script behavior using dry-run mode:
```bash
./build-image.sh --dry-run
./build-image.sh -p Vagrant-parallels -a aarch64 --dry-run
```

---

## Commit & Development Guidelines
- Maintain strict bash compatibility and standard formatting.
- Keep comments high-value, focusing on *why* logic exists (e.g. QEMU `virt` machine requirement, zstd header magic bytes).
- Always run `./test-build-image.sh` before finalizing changes.
