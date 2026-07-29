# Parallels Guest Tools ISO Directory

Place the Parallels Tools installer ISO image in this folder prior to building with the `Vagrant-parallels` profile or passing `--parallels-dir`:

- `prl-tools-lin.iso` for `x86_64`
- `prl-tools-lin-arm.iso` for `aarch64`

When building the `Vagrant-parallels` image, the script will automatically mount this directory into the build container and run the unattended Parallels Guest Tools installer.
