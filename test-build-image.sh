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

# Test 2: Default dry-run behavior (should use docker, Cloud profile, and leap box)
echo "Test 2: Verification of default dry-run behavior..."
dry_output=$(./build-image.sh --dry-run)
assert_contains "$dry_output" "Container Engine:[[:space:]]+docker" "Default engine should be docker"
assert_contains "$dry_output" "Profile:[[:space:]]+Cloud" "Default profile should be Cloud"
assert_contains "$dry_output" "KIWI Box:[[:space:]]+leap" "Default box should be leap"
assert_contains "$dry_output" "docker run -it? --rm --privileged" "Dry run command should start with docker run"
assert_contains "$dry_output" "dp.apps.rancher.io/containers/kiwi:10" "Should run the rancher kiwi:10 container"
assert_contains "$dry_output" "--set-repo https://download.opensuse.org/distribution/leap/15.6/repo/oss" "Should set Leap 15.6 repo by default"
assert_contains "$dry_output" "--profile Cloud" "Should set profile Cloud by default"
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

echo "=================================================="
echo "ALL TESTS PASSED SUCCESSFULLY!"
echo "=================================================="
