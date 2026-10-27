# `rust-binary-release.yml`

The build-and-attach half of a CLI crate's release. It runs as a second job
behind `rust-release.yml`, which still owns the tag and the release.

```yaml
jobs:
  release:
    uses: GregorLueg/personal-actions/.github/workflows/rust-release.yml@v1
    with:
      publish-args: '--features hdf5-static'
    secrets: inherit

  binaries:
    needs: release
    uses: GregorLueg/personal-actions/.github/workflows/rust-binary-release.yml@v1
    with:
      binary: splatter-sc
      build-args: '--features hdf5-static'
      windows: false
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `binary` | string | required | Cargo binary target. Assets are `<binary>-<target>.tar.gz`, `.zip` on Windows. |
| `build-args` | string | `''` | Appended to `cargo build --release`. |
| `windows` | boolean | `true` | Adds `x86_64-pc-windows-msvc` next to `x86_64-unknown-linux-gnu` and `aarch64-apple-darwin`. |
| `timeout-minutes` | number | `30` | Per build job. |

It reads `v$version` from `[package]` with the same awk as `rust-release.yml`,
then compares the release's assets against the matrix. The calling `release`
job runs on every green test of the default branch, not just on a version
bump, so without that check every push would rebuild and re-upload the same
binaries. Missing assets, or a `workflow_dispatch`, trigger a build.

Builds check out the tag rather than the triggering ref, so a manual re-run of
an older release ships that release's code. Uploading goes through `gh release
upload --clobber`, which replaces assets but leaves the release's name, notes
and "Latest" flag alone. The Linux binary links against the glibc of
`ubuntu-latest` and will not run on older distributions.
