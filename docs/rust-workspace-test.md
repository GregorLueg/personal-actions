# `rust-workspace-test.yml`

For a repo that is a cargo workspace of crates published together, like
`bixverse-rs` since 0.8.0. Not a superset of `rust-test.yml`, so a separate
file rather than more inputs on that one.

```yaml
jobs:
  test:
    uses: GregorLueg/personal-actions/.github/workflows/rust-workspace-test.yml@v1
    with:
      cpu-runs: |
        -p bixverse-core
        -p bixverse-sc-data --features h5
        -p bixverse-rs --features single-cell,multi-modal,hdf5-static
      r-runs: |
        -p bixverse-r --features single-cell,multi-modal
      gpu-runs: |
        -p bixverse-gpu
        -p bixverse-rs --features sc-gpu,hdf5-static
      check-exclude: bixverse-r
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `cpu-runs` | string | `''` | `cargo test` runs, one per line. No R on this lane, so Windows stays on msvc. Empty skips it. |
| `windows-cpu-runs` | string | `''` | Overrides `cpu-runs` on Windows. |
| `r-runs` | string | `''` | Same, on a lane with R and the shared libR, gnu ABI on Windows. Empty skips it. |
| `gpu-runs` | string | `''` | Same, on the Linux lavapipe and macOS GPU lane. Empty skips it. |
| `check-members` | boolean | `true` | `cargo check -p <member> --no-default-features --all-targets` for every member on its own. |
| `check-exclude` | string | `''` | Members the check job skips, space separated. |
| `windows` | boolean | `true` | Include `windows-latest` in the CPU and R matrices. |
| `gpu-malloc-check` | boolean | `false` | As in [`rust-test.yml`](rust-test.md). |
| `timeout-minutes` | number | `45` | |

The check job is there because of feature unification. A workspace-wide build
turns on every feature any member asks for, so a member that forgot to declare
one compiles in the workspace and breaks for a consumer that depends on it
alone. Checking each member by itself is the only build that sees that. It has
no R: extendr's build script looks for R even under `cargo check`, so a member
that links libR goes in `check-exclude` and is covered by the R lane instead.

R is a lane of its own because only the member that links libR needs it. Every
other crate tests without R, which is most of the point of splitting the R
layer out.
