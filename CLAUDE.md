# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

Packaging repo for the **violoop-pro** aarch64 cross-compile toolchain. It produces two Docker images and publishes a tarball release. No application code lives here — only the Dockerfiles, the vendored ARM GNU toolchain (`violoop-pro/toolchain/`), a sysroot copied from the target device (`violoop-pro/sysroot/`), and a CMake toolchain file.

The repo is binary-heavy on purpose (README warns not to clone casually).

## Common commands

Build images (must build `base` first, since `violoop-pro` `FROM builder:base`):

```bash
docker build -t builder:base base
docker build -t builder:violoop-pro violoop-pro
```

Cut a release — bumps `version`, commits, tags `vX.Y.Z`, and pushes. The push of a `v*` tag triggers `.github/workflows/publish.yml`, which tars `violoop-pro/` into `aarch64-none-linux-gnu.tar.gz` and uploads it as a GitHub Release asset.

```bash
./scripts/version.sh              # bumps patch
./scripts/version.sh minor        # or major / patch
```

Consume the toolchain inside the `builder:violoop-pro` container (files land at `/workspace/`):

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=/workspace/toolchain.cmake ..
```

## Architecture notes worth knowing before editing

- **Paths in `violoop-pro/toolchain.cmake` are absolute (`/workspace/...`)** and only resolve inside `builder:violoop-pro`, because that image's Dockerfile `COPY`s `toolchain/`, `sysroot/`, and `toolchain.cmake` into `/workspace/`. If you rename any of those three sources, update both the Dockerfile and `toolchain.cmake` together.
- **Toolchain version is pinned** to `arm-gnu-toolchain-12.3.rel1-x86_64-aarch64-none-linux-gnu` inside `toolchain.cmake`. Swapping the toolchain directory requires editing that path — there is no glob.
- **`sysroot/lib` is a symlink to `usr/lib`**; preserve it when refreshing the sysroot from a target device.
- **Release artifact structure matters.** The workflow runs `tar -czf aarch64-none-linux-gnu.tar.gz -C violoop-pro .`, so anything added at `violoop-pro/` top level ships to consumers. Don't drop build/scratch files there.
- **`scripts/version.sh` pushes immediately** (commit + tag + `git push --tags`). It is not a dry-run tool — running it publishes a release.
