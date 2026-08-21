# personal-actions

Reusable GitHub Actions workflows for my R packages, Rust crates and Python
packages. The CI logic lives here once. Consuming repos keep a thin caller
pinned to `@v1`, so fixing a cache key is one commit plus a tag move rather than
eleven PRs.

Scaffolding that has to exist inside each repo, the callers included, is shipped
by the copier template in
[personal-templates](https://github.com/GregorLueg/personal-templates).

## Workflows

| workflow | for |
|---|---|
| `r-cmd-check.yml` | R CMD check, with or without a Rust crate |
| `r-pkgdown.yml` | Build the pkgdown site, deploy on non-PR events |
| `r-auto-tag.yml` | Tag and release on a version bump, gated on a green check |
| `rust-test.yml` | Crate tests, CPU and GPU lanes |
| `rust-release.yml` | Tag, release and `cargo publish`, gated on a green test |
| `python-test.yml` | ruff, ty and pytest over an OS x interpreter matrix |
| `python-release.yml` | Tag, release and `uv publish`, gated on a green test |

Consumers: five R packages, six Rust crates and one Python package.
`node2vec-rs` uses `rust-test.yml` but keeps a bespoke release, because it
cross-compiles binaries for three targets and attaches them as release assets.

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
| `rust` | boolean | `true` | Sets up the toolchain and sccache. Keep it on for a pure-R package that builds a rextendr dependency from source. |
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

### `rust-test.yml`

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
| `gpu-args` | string | `''` | GPU lane args. **Empty skips the GPU job entirely**, which is what `node2vec-rs` wants. |
| `windows` | boolean | `true` | Include `windows-latest` in the CPU matrix. |
| `needs-r` | boolean | `false` | Installs R and the shared libR, and switches Windows to the gnu ABI. `bixverse-rs` links against R via extendr. |
| `gpu-malloc-check` | boolean | `false` | `MALLOC_CHECK_=3` on the Linux GPU lane. |
| `timeout-minutes` | number | `30` | |

Caching is `Swatinem/rust-cache@v2` with `cache-on-failure`, keyed per OS and
separately for the GPU lane. On Windows the workspace and `~/.cargo` are excluded
from Defender first: it scans every file cargo and the cache extractor touch,
which is a large multiplier on an IO-bound job.

The Linux GPU lane has no real GPU and falls back to lavapipe software Vulkan.
Treat it as a smoke lane that covers the shared-memory reduction arm and SPIR-V
codegen, neither of which Apple exercises. `gpu-malloc-check` is off by default
because turning it on can legitimately turn a currently-green lane red: under
lavapipe a kernel writing past a shared-memory allocation is a real heap
overflow, and glibc will abort at the next free.

### `rust-release.yml`

Same shape as `r-auto-tag.yml`: triggered by a completed test run, not a push.

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

### `python-test.yml`

```yaml
name: Python test
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
    uses: GregorLueg/personal-actions/.github/workflows/python-test.yml@v1
    with:
      python-versions: '["3.12","3.13"]'
      windows: false
```

| input | type | default | what it does |
|---|---|---|---|
| `python-versions` | string | `'["3.12","3.13"]'` | JSON array. A string because `workflow_call` inputs cannot be lists. |
| `windows` | boolean | `false` | Adds `windows-latest` to the matrix. |
| `macos` | boolean | `true` | Adds `macos-latest` to the matrix. |
| `sync-args` | string | `--all-extras` | Appended to `uv sync`. Pulls every extra so optional backends are import-checked. |
| `test-args` | string | `''` | Appended to `uv run pytest`, e.g. `-m 'not integration'`. |
| `ty` | boolean | `true` | Run `uv run ty check`. |
| `ty-required` | boolean | `true` | Whether a ty diagnostic fails the lint job. |
| `timeout-minutes` | number | `20` | |

Windows is off by default here and on in `rust-test.yml`. The Python consumers
are data pipelines, not cross-platform libraries, so Windows path handling is a
cost nobody is paying for yet.

Lint and typecheck live in their own Linux-only job. Neither result varies by OS
or interpreter, so running them once beats reporting the same ruff failure six
times. `uv lock --check` runs alongside them: a lockfile that has drifted from
`pyproject.toml` makes every other result meaningless.

`ty-required: false` is the incremental-adoption knob. ty still runs and its
output is in the log, it just does not gate the merge. Use it while annotating
an existing codebase, and delete it once the diagnostics are at zero.

### `python-release.yml`

Same shape as `rust-release.yml`: triggered by a completed test run, not a push.

```yaml
name: Release
on:
  workflow_run:
    workflows: ["Python test"]
    branches: [main]
    types: [completed]
  workflow_dispatch:
permissions:
  contents: write
  id-token: write
jobs:
  release:
    uses: GregorLueg/personal-actions/.github/workflows/python-release.yml@v1
```

| input | type | default | what it does |
|---|---|---|---|
| `publish` | boolean | `true` | Set false to tag and release on GitHub without distributing. |
| `build-args` | string | `''` | Appended to `uv build`, e.g. `--sdist`. |
| `timeout-minutes` | number | `20` | |

It reads `name` and `version` from the `[project]` table in `pyproject.toml`,
then runs the same two **independent** gates as `rust-release.yml`:

- tag `v$version` missing -> create the tag and cut a release with generated notes
- `$version` missing from PyPI -> `uv build` and `uv publish`

The PyPI check is `GET https://pypi.org/pypi/{name}/{version}/json`. Anything
that is neither 200 nor 404 fails the job. Yanked versions return 200, so a yank
never triggers a republish.

**No `secrets: inherit` here, and no API token.** Publishing goes through PyPI
trusted publishing over OIDC, which is why the caller needs `id-token: write`.
That means a one-off setup step: add a trusted publisher on PyPI for the repo,
naming this workflow file, before the first release. Without it the publish step
403s. `--trusted-publishing always` rather than `automatic`, so a missing OIDC
token is an error instead of a silent fallback to a token that does not exist.

**`uv publish` is irreversible.** PyPI will not accept a re-upload of a version
or even of a filename, so the PyPI check is the only thing standing between a
merge and a permanent mistake. It runs before anything is pushed anywhere.

## Versioning

Callers pin `@v1`. Releases are tagged `vX.Y.Z` and the major tag moves to point
at the newest compatible release.

`main` moving is inert: nothing consumes it. **Moving `v1` is the deployment.**
Do that only after one consumer has gone green on the new sha, because a bad
`v1` reaches eleven repos at once. Rolling back is moving the tag again.

Note the contrast with
[personal-templates](https://github.com/GregorLueg/personal-templates), which
takes plain version tags and no moving major. Copier resolves the newest tag by
itself, so a moving tag there would confuse it. Same author, opposite
discipline, which is why they are two repos.

## Testing

`smoke.yml` runs actionlint on every workflow here. It cannot run them
end to end: `actions/checkout` inside a `workflow_call` checks out the calling
repo, so there is no way to point one at a fixture package without a separate
fixture repo. The real integration test is the first consumer going green.

Worth knowing what that leaves untested. Every path here has now run in anger
except two: `cargo publish` in `rust-release.yml`, which only fires on a real
version bump, and the `rust: false` input on the R workflows, which no package
currently sets.

The publish path is worth the extra care for that reason. Before moving `v1`
after a change to `rust-release.yml`, point one consumer's caller at the branch
(`rust-release.yml@<branch>` is valid) and dispatch it, rather than deploying to
six crates on an untested path.
