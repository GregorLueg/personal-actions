# personal-actions

Reusable GitHub Actions workflows for my R packages and Rust crates. The CI
logic lives here once. Consuming repos keep a thin caller pinned to `@v1`, so
fixing a cache key is one commit plus a tag move rather than eleven PRs.

Scaffolding that has to exist inside each repo, the callers included, is shipped
by the copier template in
[personal-templates](https://github.com/GregorLueg/personal-templates).

## Workflows

| workflow | for |
|---|---|
| `r-cmd-check.yml` | R CMD check, with or without a Rust crate |
| `r-pkgdown.yml` | Build the pkgdown site, deploy on non-PR events |
| `r-auto-tag.yml` | Tag and release on a version bump, gated on a green check |

More to follow: `rust-test.yml`, `rust-release.yml`.

### `r-cmd-check.yml`

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
| `rust` | boolean | `true` | Sets up the toolchain and sccache. Off for pure-R packages. |
| `rust-toolchain` | string | `stable` | Pin a version, e.g. `1.91.0`. The gnu suffix is appended on Windows. |
| `gpu` | boolean | `false` | Installs Vulkan on Linux, sets `WGPU_BACKEND=vulkan`. |
| `windows` | boolean | `true` | Adds `windows-latest` to the matrix. |
| `linux-runner` | string | `ubuntu-latest` | Pin to `ubuntu-22.04` where the toolchain needs it. |
| `extra-sysdeps` | string | `''` | Extra apt packages, space separated. |
| `rebuild-from-source` | string | `''` | R packages to reinstall from source on macOS after pak. |

On Windows the Rust toolchain is `stable-x86_64-pc-windows-gnu`, because extendr
links against the gnu ABI rather than msvc.

If the repo has a `.copier-answers.yml`, a Linux-only step warns on template
drift. It never fails the build: a repo mid-release should not be blocked
because the template moved.

### `r-pkgdown.yml`

```yaml
name: pkgdown
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  release:
    types: [published]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  pkgdown:
    uses: GregorLueg/personal-actions/.github/workflows/r-pkgdown.yml@v1
    with:
      rust: true
      gpu: false
    secrets: inherit
```

Inputs are `rust`, `gpu` and `extra-sysdeps`, same meaning as above. The deploy
step is guarded by `github.event_name != 'pull_request'`, so a PR builds the
site to prove it builds and publishes nothing.

### `r-auto-tag.yml`

This one is triggered by a **completed check run, not by a push**, so a broken
package can never be tagged. Wire it up like this:

```yaml
name: Auto tag
on:
  workflow_run:
    workflows: ["R-CMD-check"]
    branches: [main]
    types: [completed]
  workflow_dispatch:
permissions:
  contents: write
jobs:
  tag:
    uses: GregorLueg/personal-actions/.github/workflows/r-auto-tag.yml@v1
    secrets: inherit
```

`workflows:` must match the `name:` of that repo's check workflow. The job is
skipped unless the run succeeded on the default branch, so pointing this at a
`push` trigger silently does nothing. It reads `Version` from `DESCRIPTION`,
does nothing if `v$Version` already exists, and otherwise tags and cuts a
release with generated notes.

There is no `paths: [DESCRIPTION]` filter and none is needed. The job runs after
every green check on the default branch, finds the tag present and exits in
about two seconds.

Declare `permissions: contents: write` in the caller. A called workflow's
permissions are capped by the caller's token, so leaving it out can make the tag
push fail on repos whose default token is read-only.

## Versioning

Callers pin `@v1`. Releases are tagged `vX.Y.Z` and the major tag moves to
point at the newest compatible release.

Move `v1` only after one consumer has gone green on the new sha. A bad `v1`
takes down every repo at once, so after the first tag `main` is protected and
changes go through a PR.

## Testing

`smoke.yml` runs actionlint on every workflow here. It cannot run them
end to end: `actions/checkout` inside a `workflow_call` checks out the calling
repo, so there is no way to point one at a fixture package without a separate
fixture repo. The real integration test is the first consumer going green.
