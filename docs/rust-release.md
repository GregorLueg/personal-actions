# `rust-release.yml`

Same shape as [`r-auto-tag.yml`](r-auto-tag.md): triggered by a completed test run, not a push.

```yaml
name: Release
on:
  workflow_run:
    workflows: ["Test the package"]
    branches: [main]
    types: [completed]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  release:
    uses: GregorLueg/personal-actions/.github/workflows/rust-release.yml@v1
    with:
      publish-args: '--features parametric,fft_tsne,gpu'
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `publish-args` | string | `''` | Appended to `cargo publish`, e.g. `--features binary,gpu` or `--no-verify`. |
| `needs-r` | boolean | `false` | The publish verification build links against R. |
| `python-owns-latest` | boolean | `false` | Leave GitHub's "Latest" release to the `py-v*` bindings release. Only for a repo that ships both: mkdocs-material's header reads the latest release with no tag filter. A crate without bindings must leave it off, or its repo shows no "Latest" at all. |
| `timeout-minutes` | number | `30` | |

It reads `name` and `version` from the `[package]` table in `Cargo.toml`, then
runs two **independent** gates:

- tag `v$version` missing -> create the tag and cut a release with generated notes
- `$version` missing from crates.io -> install the toolchain and publish

Nothing links the two. A run that dies between them, which is how `bixverse-rs`
0.4.5 ended up tagged but never published, is recoverable: rerun the caller's
`workflow_dispatch` and the tag half skips while the publish half proceeds. The
next green test on `main` heals it too, so the dispatch is convenience rather
than the only route. When the tag already existed, the publish checks that tag
out first, so what lands on crates.io is what the release tag points at.

The crates.io check is `GET /api/v1/crates/{name}/{version}`. Anything that is
neither 200 nor 404 fails the job: a transient 5xx must not be read as "not
published". Yanked versions return 200, so a yank never triggers a republish.

`secrets: inherit` is not optional here: the publish step needs
`CARGO_REGISTRY_TOKEN`.

**`cargo publish` is irreversible.** crates.io will not accept a re-upload of a
version, so the crates.io check is the only thing standing between a merge and a
permanent mistake. It runs before anything is pushed anywhere.

The `timeout-minutes` default matters more here than in `rust-test.yml`. Without
it the job inherits GitHub's 6-hour cap, and an `apt-get install r-base-dev`
that wedges on a bad mirror will happily use all of it, which is exactly what
broke the 0.4.5 release.
