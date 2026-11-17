# `rust-test.yml`

```yaml
name: Test the package
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    uses: GregorLueg/personal-actions/.github/workflows/rust-test.yml@v1
    with:
      cpu-args: '--release --no-default-features'
      gpu-args: '--release --features gpu,parametric,fft_tsne'
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `cpu-args` | string | `''` | Appended to `cargo test` on the CPU lane. |
| `cpu-args-extra` | string | `''` | A second `cargo test` run. Only `bixverse-rs` needs one. |
| `windows-cpu-args` | string | `''` | Overrides `cpu-args` on Windows. `ann-search-rs` drops `gpu` there. |
| `gpu-args` | string | `''` | GPU lane args. **Empty skips the GPU job entirely**, which is what `node2vec-rs` wants. When set, the CPU lane runs on Windows only. |
| `windows` | boolean | `true` | Include `windows-latest` in the CPU matrix. |
| `needs-r` | boolean | `false` | Installs R and the shared libR, and switches Windows to the gnu ABI. `bixverse-rs` links against R via extendr. |
| `gpu-malloc-check` | boolean | `false` | `MALLOC_CHECK_=3` on the Linux GPU lane. |
| `timeout-minutes` | number | `30` | |

When `gpu-args` is set, the GPU lane on Linux and macOS stands in for the CPU
lane there, so the CPU lane keeps only Windows, which has no GPU lane. That
assumes `gpu-args` covers what `cpu-args` tests. A `--no-default-features` CPU
lane is then only exercised on Windows; with `windows: false` the CPU job is
skipped entirely.

Caching is `Swatinem/rust-cache@v2` with `cache-on-failure`, keyed per OS and
separately for the GPU lane. Only the default branch saves: a PR cache is scoped
to the PR's ref, so nothing else can restore it, and it evicts the default
branch's caches under the 10 GB repo cap. PRs restore from the default branch.
On Windows the workspace and `~/.cargo` are excluded
from Defender first: it scans every file cargo and the cache extractor touch,
which is a large multiplier on an IO-bound job.

The Linux GPU lane has no real GPU and falls back to lavapipe software Vulkan.
Treat it as a smoke lane that covers the shared-memory reduction arm and SPIR-V
codegen, neither of which Apple exercises. `gpu-malloc-check` is off by default
because turning it on can legitimately turn a currently-green lane red: under
lavapipe a kernel writing past a shared-memory allocation is a real heap
overflow, and glibc will abort at the next free.
