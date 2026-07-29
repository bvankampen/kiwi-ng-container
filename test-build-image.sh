#!/usr/bin/env bash

# test-build-image.sh - Test suite for build-image.sh script
# Verifies that options, defaults, and engine configurations are handled correctly.

set -euo pipefail

echo "=================================================="
echo "Running build-image.sh test suite..."
echo "=================================================="

# Create a clean temporary directory for test isolated runs
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Copy script to temp directory for testing
cp ./build-image.sh "$TEST_DIR/build-image.sh"
cp ./run-image.sh "$TEST_DIR/run-image.sh"
cd "$TEST_DIR"

# Helper function to assert output matches a pattern
assert_contains() {
    local text="$1"
    local pattern="$2"
    local message="$3"
    if [[ ! "$text" =~ $pattern ]]; then
        echo "FAIL: $message" >&2
        echo "Expected pattern: $pattern" >&2
        echo "Actual text:" >&2
        echo "$text" >&2
        exit 1
    fi
}

# Helper function to assert command failure
assert_fails() {
    local cmd="$1"
    local message="$2"
    if eval "$cmd" &>/dev/null; then
        echo "FAIL: $message (expected failure, but succeeded)" >&2
        exit 1
    fi
}

# Test 1: Help message
echo "Test 1: Verification of help output..."
help_output=$(./build-image.sh --help)
assert_contains "$help_output" "Usage:" "Help output should contain Usage instruction"
assert_contains "$help_output" "Options:" "Help output should list options"
assert_contains "$help_output" "Build an OpenSUSE Leap" "Help output should describe script purpose"
echo "  [PASS]"

# Test 2: Default dry-run behavior (should use docker, Vagrant profile, and leap box)
echo "Test 2: Verification of default dry-run behavior..."
dry_output=$(./build-image.sh --dry-run)
assert_contains "$dry_output" "Container Engine:[[:space:]]+docker" "Default engine should be docker"
assert_contains "$dry_output" "Profile:[[:space:]]+Vagrant" "Default profile should be Vagrant"
assert_contains "$dry_output" "KIWI Box:[[:space:]]+leap" "Default box should be leap"
assert_contains "$dry_output" "docker run -it? --rm --privileged" "Dry run command should start with docker run"
assert_contains "$dry_output" "dp.apps.rancher.io/containers/kiwi:10" "Should run the rancher kiwi:10 container"
assert_contains "$dry_output" "--set-repo https://download.opensuse.org/distribution/leap/15.6/repo/oss" "Should set Leap 15.6 repo by default"
assert_contains "$dry_output" "--profile Vagrant" "Should set profile Vagrant by default"
assert_contains "$dry_output" "--box leap" "Should set box leap by default"
echo "  [PASS]"

# Test 3: Override engine via -e flag
echo "Test 3: Override engine via command line flag..."
dry_podman=$(./build-image.sh --dry-run -e podman)
assert_contains "$dry_podman" "Container Engine:[[:space:]]+podman" "Engine should be podman"
assert_contains "$dry_podman" "podman run -it? --rm --privileged" "Command should start with podman run"
echo "  [PASS]"

# Test 4: Override engine via CONTAINER_ENGINE environment variable
echo "Test 4: Override engine via environment variable..."
dry_env=$(CONTAINER_ENGINE=podman ./build-image.sh --dry-run)
assert_contains "$dry_env" "Container Engine:[[:space:]]+podman" "Engine should be podman from env"
assert_contains "$dry_env" "podman run -it? --rm --privileged" "Command should use podman from env"
echo "  [PASS]"

# Test 5: Custom directory arguments
echo "Test 5: Verification of custom paths..."
dry_custom=$(./build-image.sh --dry-run -o ./custom_out -c ./custom_cache -d ./custom_desc)
assert_contains "$dry_custom" "Output Dir:[[:space:]]+.*/custom_out" "Output dir should be resolved to absolute custom_out"
assert_contains "$dry_custom" "Cache Dir:[[:space:]]+.*/custom_cache" "Cache dir should be resolved to absolute custom_cache"
assert_contains "$dry_custom" "Description Dir:[[:space:]]+.*/custom_desc" "Desc dir should be resolved to absolute custom_desc"
assert_contains "$dry_custom" "--volume .*/custom_desc:/image_description" "Volume mount should use custom description dir"
assert_contains "$dry_custom" "--volume .*/custom_out:/target_image" "Volume mount should use custom output dir"
assert_contains "$dry_custom" "--volume .*/custom_cache:/.kiwi_boxes" "Volume mount should use custom cache dir"
echo "  [PASS]"

# Test 6: Custom repo URL
echo "Test 6: Verification of custom repository URL..."
dry_repo=$(./build-image.sh --dry-run -r https://example.com/custom-repo)
assert_contains "$dry_repo" "Repository URL:[[:space:]]+https://example.com/custom-repo" "Repo URL should match custom argument"
assert_contains "$dry_repo" "--set-repo https://example.com/custom-repo" "Build command should receive custom repo URL"
echo "  [PASS]"

# Test 7: Invalid engine validation
echo "Test 7: Validation of invalid engine..."
assert_fails "./build-image.sh --dry-run -e invalid_engine" "Should fail with invalid container engine"
echo "  [PASS]"

# Test 8: Custom profile via -p flag
echo "Test 8: Verification of custom profile via command line flag..."
dry_profile=$(./build-image.sh --dry-run -p VMware)
assert_contains "$dry_profile" "Profile:[[:space:]]+VMware" "Profile should be VMware"
assert_contains "$dry_profile" "--profile VMware" "Build command should receive --profile VMware"
echo "  [PASS]"

# Test 9: Custom profile via KIWI_PROFILE environment variable
echo "Test 9: Verification of custom profile via environment variable..."
dry_profile_env=$(KIWI_PROFILE=kvm-and-xen ./build-image.sh --dry-run)
assert_contains "$dry_profile_env" "Profile:[[:space:]]+kvm-and-xen" "Profile should be kvm-and-xen from env"
assert_contains "$dry_profile_env" "--profile kvm-and-xen" "Build command should receive --profile kvm-and-xen from env"
echo "  [PASS]"

# Test 10: Custom box via -b flag
echo "Test 10: Verification of custom box via command line flag..."
dry_box=$(./build-image.sh --dry-run -b custom_box)
assert_contains "$dry_box" "KIWI Box:[[:space:]]+custom_box" "Box should be custom_box"
assert_contains "$dry_box" "--box custom_box" "Build command should receive --box custom_box"
echo "  [PASS]"

# Test 11: Custom box via KIWI_BOX environment variable
echo "Test 11: Verification of custom box via environment variable..."
dry_box_env=$(KIWI_BOX=tumbleweed ./build-image.sh --dry-run)
assert_contains "$dry_box_env" "KIWI Box:[[:space:]]+tumbleweed" "Box should be tumbleweed from env"
assert_contains "$dry_box_env" "--box tumbleweed" "Build command should receive --box tumbleweed from env"
echo "  [PASS]"

# Test 12: List boxes option in dry-run mode
echo "Test 12: Verification of list-boxes dry-run output..."
dry_list_boxes=$(./build-image.sh --dry-run --list-boxes)
assert_contains "$dry_list_boxes" "system boxbuild --list-boxes" "Should invoke list-boxes command"
echo "  [PASS]"

# Test 13: Vagrant-parallels profile and custom parallels-dir
echo "Test 13: Verification of Vagrant-parallels profile and parallels volume mount..."
dry_parallels=$(./build-image.sh --dry-run -p Vagrant-parallels -s ./custom_parallels)
assert_contains "$dry_parallels" "Profile:[[:space:]]+Vagrant-parallels" "Profile should be Vagrant-parallels"
assert_contains "$dry_parallels" "Parallels Dir:[[:space:]]+.*/custom_parallels" "Parallels dir should be resolved"
assert_contains "$dry_parallels" "--volume .*/custom_parallels:/image_description/root/tmp/parallels_iso" "Should mount parallels ISO dir into overlay"
echo "  [PASS]"

# Test 14: Target architecture override via -a flag (auto-switches box to universal and sets --machine virt)
echo "Test 14: Verification of aarch64 target architecture override via -a flag..."
dry_arch=$(./build-image.sh --dry-run -a aarch64)
assert_contains "$dry_arch" "Target Arch:[[:space:]]+aarch64" "Target arch should be aarch64"
assert_contains "$dry_arch" "KIWI Box:[[:space:]]+universal" "Default box should auto-switch to universal for aarch64"
assert_contains "$dry_arch" "QEMU Machine:[[:space:]]+virt" "Machine should default to virt for aarch64"
assert_contains "$dry_arch" "--box universal --aarch64 --machine virt" "Command should pass --box universal --aarch64 --machine virt"
echo "  [PASS]"

# Test 15: Target architecture via KIWI_TARGET_ARCH environment variable
echo "Test 15: Verification of aarch64 target architecture via environment variable..."
dry_arch_env=$(KIWI_TARGET_ARCH=aarch64 ./build-image.sh --dry-run)
assert_contains "$dry_arch_env" "Target Arch:[[:space:]]+aarch64" "Target arch should be aarch64 from env"
assert_contains "$dry_arch_env" "--aarch64" "Command should pass --aarch64 from env"
echo "  [PASS]"

# Test 16: Auto-detection of aarch64 architecture for RaspberryPi profile
echo "Test 16: Verification of auto aarch64 detection for RaspberryPi profile..."
dry_rpi=$(./build-image.sh --dry-run -p RaspberryPi)
assert_contains "$dry_rpi" "Target Arch:[[:space:]]+aarch64" "RaspberryPi profile should auto-detect aarch64"
assert_contains "$dry_rpi" "KIWI Box:[[:space:]]+universal" "RaspberryPi profile should auto-switch box to universal"
assert_contains "$dry_rpi" "--aarch64" "Command should pass --aarch64 for RaspberryPi profile"
echo "  [PASS]"

# Test 17: Validation of invalid target architecture
echo "Test 17: Validation of invalid target architecture..."
assert_fails "./build-image.sh --dry-run -a invalid_arch" "Should fail with invalid target architecture"
echo "  [PASS]"

# Test 18: Verification of --no-parallels flag skipping volume mount
echo "Test 18: Verification of --no-parallels flag..."
dry_no_par=$(./build-image.sh --dry-run --no-parallels -s ./custom_parallels)
assert_contains "$dry_no_par" "Parallels Tools:[[:space:]]+false" "Parallels tools should be set to false"
if [[ "$dry_no_par" =~ /tmp/parallels_iso ]]; then
    echo "FAIL: --no-parallels should not mount parallels_iso" >&2
    exit 1
fi
echo "  [PASS]"

# Test 19: Verification of --with-parallels flag enabling volume mount
echo "Test 19: Verification of --with-parallels flag..."
dry_with_par=$(./build-image.sh --dry-run --with-parallels -s ./custom_parallels)
assert_contains "$dry_with_par" "Parallels Tools:[[:space:]]+true" "Parallels tools should be set to true"
assert_contains "$dry_with_par" "--volume .*/custom_parallels:/image_description/root/tmp/parallels_iso" "Should mount parallels ISO dir when --with-parallels is passed"
echo "  [PASS]"

# Test 20: Verification of WITH_PARALLELS=false environment variable
echo "Test 20: Verification of WITH_PARALLELS environment variable..."
dry_par_env=$(WITH_PARALLELS=false ./build-image.sh --dry-run -s ./custom_parallels)
assert_contains "$dry_par_env" "Parallels Tools:[[:space:]]+false" "Parallels tools should be false from env"
if [[ "$dry_par_env" =~ /tmp/parallels_iso ]]; then
    echo "FAIL: WITH_PARALLELS=false should not mount parallels_iso" >&2
    exit 1
fi
echo "  [PASS]"

# Test 21: Verification of run-image.sh help output and dry-run
echo "Test 21: Verification of run-image.sh dry-run output..."
dry_run_img=$(./run-image.sh --dry-run)
assert_contains "$dry_run_img" "entrypoint qemu-system-x86_64" "run-image.sh should use qemu entrypoint"
assert_contains "$dry_run_img" "-drive file=/target_image/" "run-image.sh should attach target image"
echo "  [PASS]"

# Test 22: Verification of run-image.sh with Parallels ISO
echo "Test 22: Verification of run-image.sh with Parallels ISO attachment..."
dry_run_par=$(./run-image.sh --dry-run --with-parallels -s ./custom_iso.iso)
assert_contains "$dry_run_par" "-drive file=/parallels_iso/.*media=cdrom" "run-image.sh should mount Parallels ISO as CD-ROM"
echo "  [PASS]"

# Test 23: Verification of run-image.sh --no-parallels
echo "Test 23: Verification of run-image.sh --no-parallels..."
dry_run_nopar=$(./run-image.sh --dry-run --no-parallels)
assert_contains "$dry_run_nopar" "Parallels ISO:[[:space:]]+Disabled/Not attached" "run-image.sh should disable Parallels ISO"
if [[ "$dry_run_nopar" =~ media=cdrom ]]; then
    echo "FAIL: run-image.sh --no-parallels should not attach CD-ROM drive" >&2
    exit 1
fi
echo "  [PASS]"

# Test 24: Verification of auto-switching Vagrant profile to Vagrant-parallels when MOUNT_PARALLELS resolves to true
echo "Test 24: Verification of auto-switching to Vagrant-parallels..."
dry_autoswitch=$(./build-image.sh --dry-run --with-parallels)
assert_contains "$dry_autoswitch" "Profile:[[:space:]]+Vagrant-parallels" "Should auto-switch default Vagrant profile to Vagrant-parallels when --with-parallels is passed"
assert_contains "$dry_autoswitch" "--profile Vagrant-parallels" "Should pass --profile Vagrant-parallels to KIWI"
echo "  [PASS]"

# Test 25: Verification that explicit profiles are NOT overridden by auto-switching
echo "Test 25: Verification that explicit profiles are preserved..."
dry_explicit_preserved=$(./build-image.sh --dry-run -p VMware --with-parallels)
assert_contains "$dry_explicit_preserved" "Profile:[[:space:]]+VMware" "Explicit profile VMware should be preserved even with --with-parallels"
assert_contains "$dry_explicit_preserved" "--profile VMware" "Should pass explicit --profile VMware to KIWI"
echo "  [PASS]"

# Test 26: Verification that parallels_iso is NOT mounted for non-Vagrant profiles even with --with-parallels
echo "Test 26: Verification that parallels_iso is not mounted for non-Vagrant profiles..."
dry_non_vagrant_no_par=$(./build-image.sh --dry-run -p VMware --with-parallels -s ./custom_parallels)
assert_contains "$dry_non_vagrant_no_par" "Parallels Tools:.*active: false" "Parallels tools should not be active for VMware profile"
if [[ "$dry_non_vagrant_no_par" =~ /tmp/parallels_iso ]]; then
    echo "FAIL: parallels_iso should not be mounted for VMware profile" >&2
    exit 1
fi
echo "  [PASS]"

# Test 27: Custom QEMU machine flag via -m in build-image.sh
echo "Test 27: Verification of custom QEMU machine flag in build-image.sh..."
dry_machine=$(./build-image.sh --dry-run -m sbsa-ref)
assert_contains "$dry_machine" "QEMU Machine:[[:space:]]+sbsa-ref" "Summary should display custom machine"
assert_contains "$dry_machine" "--machine sbsa-ref" "Build command should pass --machine sbsa-ref"
echo "  [PASS]"

# Test 28: Verification of run-image.sh with aarch64 architecture and machine
echo "Test 28: Verification of run-image.sh aarch64 machine, cpu, and accel flags..."
dry_run_aarch64=$(./run-image.sh --dry-run -a aarch64)
assert_contains "$dry_run_aarch64" "entrypoint qemu-system-aarch64" "run-image.sh should use qemu-system-aarch64 entrypoint"
assert_contains "$dry_run_aarch64" "-machine virt" "run-image.sh should pass -machine virt for aarch64"
assert_contains "$dry_run_aarch64" "-cpu max" "run-image.sh should pass -cpu max for aarch64"
assert_contains "$dry_run_aarch64" "-accel accel=" "run-image.sh should pass -accel flag for aarch64"
echo "  [PASS]"

# Test 29: Verification of --no-accel and --cpu flags in build-image.sh
echo "Test 29: Verification of --no-accel and --cpu flags in build-image.sh..."
dry_no_accel=$(./build-image.sh --dry-run --no-accel --cpu cortex-a57)
assert_contains "$dry_no_accel" "KVM Acceleration:[[:space:]]+false" "Summary should report KVM disabled"
assert_contains "$dry_no_accel" "QEMU CPU:[[:space:]]+cortex-a57" "Summary should report cortex-a57 CPU"
assert_contains "$dry_no_accel" "--cpu cortex-a57 --no-accel" "Command should pass --cpu cortex-a57 --no-accel"
echo "  [PASS]"

# Test 31: Verification of hvf acceleration selection for aarch64 when /dev/kvm is missing
echo "Test 31: Verification of hvf acceleration selection for aarch64..."
dry_hvf=$(./build-image.sh --dry-run -a aarch64 --accel hvf)
assert_contains "$dry_hvf" "KVM Acceleration:[[:space:]]+hvf" "Summary should report hvf acceleration"
echo "  [PASS]"

# Test 30: Verification of host architecture auto-detection
echo "Test 30: Verification of host architecture auto-detection..."
host_arch_detected="$(uname -m)"
case "$host_arch_detected" in
    aarch64|arm64) EXPECTED_ARCH="aarch64" ;;
    *) EXPECTED_ARCH="x86_64" ;;
esac
dry_host_arch=$(./build-image.sh --dry-run)
assert_contains "$dry_host_arch" "Target Arch:[[:space:]]+$EXPECTED_ARCH" "Default target arch should match host arch ($EXPECTED_ARCH)"
echo "  [PASS]"

echo "=================================================="
echo "ALL TESTS PASSED SUCCESSFULLY!"
echo "=================================================="
