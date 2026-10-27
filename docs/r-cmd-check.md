# `r-cmd-check.yml`

```yaml
name: R-CMD-check
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  check:
    uses: GregorLueg/personal-actions/.github/workflows/r-cmd-check.yml@v1
    with:
      rust: true
      gpu: false
      windows: false
      linux-runner: ubuntu-22.04
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `rust` | boolean | `true` | Sets up the toolchain and sccache. Keep it on for a pure-R package that builds a rextendr dependency from source. |
| `rust-toolchain` | string | `stable` | Pin a version, e.g. `1.91.0`. The gnu suffix is appended on Windows. |
| `gpu` | boolean | `false` | Installs Vulkan on Linux, sets `WGPU_BACKEND=vulkan`. |
| `windows` | boolean | `true` | Adds `windows-latest` to the matrix. |
| `macos-x86` | boolean | `false` | Adds `macos-15-intel` to the matrix. `macOS-latest` is arm64, so this is the only way to catch x86-only numerical differences before r-universe does. |
| `linux-runner` | string | `ubuntu-latest` | Pin to `ubuntu-22.04` where the toolchain needs it. |
| `extra-repositories` | string | `''` | Extra CRAN-like repositories, comma or space separated. Use for r-universe, e.g. `https://gregorlueg.r-universe.dev`. |
| `extra-sysdeps` | string | `''` | Extra apt packages, space separated. |
| `rebuild-from-source` | string | `''` | R packages to reinstall from source on macOS after pak. |

On Windows the Rust toolchain is `stable-x86_64-pc-windows-gnu`, because extendr
links against the gnu ABI rather than msvc.

If the repo has a `.copier-answers.yml`, a Linux-only step warns on template
drift. It never fails the build: a repo mid-release should not be blocked
because the template moved.
