# CI build optimization guide

> Shared guidance for maintainers and Codex agents. Applies to GitHub Actions for ESP-IDF (ESP32-C3/S3), Raspberry Pi Pico SDK/CMake, Android/Gradle, and other projects where applicable. This is a **recommendation**, not permission to modify production CI or merge branches.

## Goals and acceptance criteria

- Reduce paid GitHub-hosted runner minutes without losing reproducibility, test coverage, firmware integrity, or reliable artifacts.
- Keep successful build artifacts associated with the exact source commit (SHA).
- Verify cache effectiveness using Actions timing and compiler cache statistics; compare cold and warm runs. Do not assume a particular speedup.
- Never suppress build failures to save runner time. Preserve at least one clean-build verification route.

## Priority order

1. **Avoid unnecessary workflow runs.** Use `on.push.paths` / `paths-ignore`, branch restrictions, or job-level changed-path checks when safe. Include shared source, config, lockfiles, submodules and workflow files in triggering patterns. Document when full regression builds must run. For jobs triggered with `pull_request`, be careful: workflow path filtering may leave required checks pending.
2. **Cancel superseded runs only when safe.** `concurrency` with `cancel-in-progress: true` is useful for iterative branches, not release/publish jobs, hardware validation, or other runs that must complete.
3. **Cache compilation outputs, not arbitrary binaries.** Prefer dedicated compiler caches (`ccache`, Gradle build cache) over restoring a whole mutable `build/` folder. Restore the cache before compilation, save it after, scope it by OS, target, toolchain/SDK and configuration, and use a deliberate invalidation strategy.
4. **Avoid configuration resets on every run.** Set the target once through checked-in project configuration or conditionally only when required. ESP-IDF `idf.py set-target` may reconfigure/clear the build directory, reducing incremental-build benefits.
5. **Build the changed platform/variant.** Do not build all ESP32 targets or all Android variants for a C3-only change unless shared code, release requirements, or regression coverage demands it.
6. **Use CI for final verification and firmware artifacts.** Local/Codex compiles can catch errors earlier, but must not silently replace the project's required clean CI checks.

## ESP-IDF 5.x (ESP32-C3 / ESP32-S3)

Prefer the pinned ESP-IDF version used by the project (for the current C3 bench: `espressif/idf:v5.5.4`). Keep Docker image versions explicit; upgrading ESP-IDF, compiler, sdkconfig, or CMake inputs can invalidate compiled results.

Enable ESP-IDF's supported ccache integration:

```bash
export IDF_CCACHE_ENABLE=1
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/ccache}"
mkdir -p "$CCACHE_DIR"
. "$IDF_PATH/export.sh"
idf.py -C targets/esp32c3 -B "$GITHUB_WORKSPACE/build-esp32c3" \
  -DIDRIVE_C3_VEHICLE_EMULATOR=ON build
ccache --show-stats || true
```

The `IDRIVE_C3_VEHICLE_EMULATOR` flag and path are **bench-specific**, not generic defaults. `set-target esp32c3` is required on first setup *unless* target is already correctly selected through `sdkconfig.defaults`, `IDF_TARGET`, or CMake project configuration. Do not drop it blindly: first inspect `sdkconfig` and the selected target. Never reuse an S3 build directory for C3.

For GitHub Actions, restore and save the `CCACHE_DIR` with `actions/cache@v4`, mounted where the build process actually runs. **Important:** workflows using `container: espressif/idf:...` must ensure the cache location is visible inside that job container (e.g. under `$GITHUB_WORKSPACE/.ccache`). Set a bounded cache size (`ccache --max-size 500M` or project-appropriate value), and key by OS/architecture, ESP-IDF version, target, and relevant toolchain/configuration. GitHub caches are immutable per key; use rolling unique keys plus a stable restore prefix to preserve cache updates. Cache misses should never make a build fail.

Do not cache `build/` as a primary optimization without first proving that CMake/Ninja state is portable and that path, target and SDK changes are safely invalidated. Merged firmware binaries must be built and verified for the current commit, not retrieved as release artifacts from a prior SHA.

## Pico SDK / RP2350 (CMake + Ninja)

- Pin Pico SDK and ARM toolchain versions; retain normal clean UF2 build semantics for releases.
- Use `ccache` as C/C++ compiler launcher (e.g. `-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache`), restoring `CCACHE_DIR` through Actions cache.
- Scope keys to compiler, Pico SDK, board (`pico2_w`), architecture, and build configuration; avoid cache mixing between incompatible targets.
- Hash the resulting UF2 and publish it as an artifact with commit SHA. Do not mistake a cached object for a validated new firmware image.

## Android / Gradle

- Use `gradle/actions/setup-gradle` caching (or the existing Gradle dependency/build cache solution), not overlapping incompatible cache systems.
- Pin JDK, Gradle wrapper and Android SDK/AGP versions; cache Gradle dependencies and eligible task outputs, not secrets, signing material or APKs as reusable build inputs.
- Build only the affected variant/modules for branch iteration; retain clean release and signed-distribution checks.
- Set short, explicit artifact retention for development APKs, and longer retention where needed for stable releases.

## Workflow hygiene

- Add `timeout-minutes` and least-privilege `permissions`. Review whether cancellation is safe.
- For non-release experiments, consider `workflow_dispatch` and narrow push filters rather than unconditional builds on every commit.
- Do not depend on generated `build/`, logs or binary artifacts to trigger a new CI run; prevent loops from CI-generated commits.
- Keep `actions/upload-artifact` for successful validated outputs. Use `retention-days` (e.g. 3–7 for bench/test artifacts), tuned to each repository's release/rollback needs.
- Document build command, tool versions, SHA256 checksums and board/target in artifact metadata.
- Never expose tokens, signing keys, credentials, personal data or proprietary logs in caches or artifacts.
- Caches are best-effort. A cold cache must still build successfully.

## Example GitHub Actions outline (adapt before applying)

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true  # ONLY for disposable iterative builds
jobs:
  firmware:
    runs-on: ubuntu-latest
    container: espressif/idf:v5.5.4
    timeout-minutes: 25
    env:
      IDF_CCACHE_ENABLE: "1"
      CCACHE_DIR: ${{ github.workspace }}/.ccache
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: .ccache
          key: ${{ runner.os }}-idf554-c3-${{ github.ref_name }}-${{ github.run_id }}
          restore-keys: |
            ${{ runner.os }}-idf554-c3-${{ github.ref_name }}-
            ${{ runner.os }}-idf554-c3-
      - name: Build
        shell: bash
        run: |
          . "$IDF_PATH/export.sh"
          ccache --max-size 500M
          # Ensure selected target is correct before omitting set-target.
          idf.py -C targets/esp32c3 -B "$GITHUB_WORKSPACE/build-esp32c3" -DIDRIVE_C3_VEHICLE_EMULATOR=ON build
          ccache --show-stats || true
```

This is an **outline, not a drop-in workflow**. Existing workflows must retain merge-bin, image verification, checksums and artifact-upload steps. Verify interpolation and cache paths in the actual job container. Consider a cache key containing a hash of lockfiles or configuration; running with `github.run_id` creates a new cache entry per run and requires periodic pruning/limits.

## Measuring impact and rollout

1. Record baseline of last ~10 successful runs: wall time, billed duration, success rate, artifact availability and failure reasons.
2. Apply **one improvement at a time** on an experimental branch; verify a cold build and 2+ warm builds.
3. Compare `ccache --show-stats`, build time, cache sizes, and unchanged firmware behavior. Validate hashes against the right source SHA; do not expect identical hashes if toolchains embed timestamps.
4. Preserve release CI with clean builds, automated smoke checks, and a manual full-rebuild trigger.
5. Review GitHub Billing usage and budgets separately. Compiler cache optimization does **not** resolve a billing/payment hold; GitHub Actions must be re-enabled through Billing independently.

## Agent instructions

Before modifying CI: inspect repo-specific workflows, project dependencies, target selection, branch protections and secrets boundaries. Propose a minimal diff and run validation. **Do not edit workflows, change required checks, merge or publish releases without explicit approval.** This document alone is not authorization to change any CI configuration.
