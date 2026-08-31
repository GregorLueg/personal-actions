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
| `python-maturin-test.yml` | The same, plus cargo, for a PyO3 extension |
| `python-maturin-release.yml` | Tag, release and a per-platform wheel matrix to PyPI |
| `python-docs.yml` | Build the mkdocs site, deploy on non-PR events |

**Two Python pairs, not one.** The `python-*` pair is for a pure-Python uv
project: `uv sync`, `uv lock --check`, `uv build`. The `python-maturin-*` pair
is for a PyO3 extension, which has a cargo workspace, no uv lockfile, a compile
step between install and test, and needs a wheel per platform rather than the
one `uv build` produces for whatever runner it lands on. Neither is a superset
of the other, which is why they are separate files rather than a pile of inputs
on one.

Consumers: five R packages, six Rust crates and two Python packages
(`ann-search-rs` is the maturin one).
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

### `python-maturin-test.yml`

For a PyO3 extension whose bindings live in a subdirectory of the crate's own
repo. Same lint/matrix split as `python-test.yml`, with cargo either side of it.

```yaml
name: Test the Python bindings
on:
  push:
    branches: [main]
    paths: ['python/**', 'src/**', 'Cargo.toml', '.github/workflows/python-test.yml']
  pull_request:
    branches: [main]
    paths: ['python/**', 'src/**', 'Cargo.toml', '.github/workflows/python-test.yml']
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  test:
    uses: GregorLueg/personal-actions/.github/workflows/python-maturin-test.yml@v1
    with:
      package: ann_search
      extra-deps: 'scikit-learn'
      cpu-only-args: '--no-default-features'
```

| input | type | default | what it does |
|---|---|---|---|
| `working-directory` | string | `python` | Where `Cargo.toml` and `pyproject.toml` live. |
| `package` | string | `''` | Import name, for `ty check`. Defaults to the directory's basename, which is wrong whenever that is `python`. |
| `python-versions` | string | `'["3.10","3.13"]'` | JSON array. |
| `macos` | boolean | `true` | |
| `windows` | boolean | `false` | |
| `maturin-args` | string | `--release` | Appended to `maturin develop`. |
| `test-args` | string | `tests -q` | Appended to `pytest`. |
| `install-args` | string | `--all-extras` | Args for `uv pip install -r pyproject.toml`. |
| `extra-deps` | string | `''` | Packages on top of the manifest, space separated. Test-only deps that do not belong in an extra. |
| `rust-lint` | boolean | `true` | `cargo fmt --check` and `cargo clippy -D warnings`. |
| `rust-test` | boolean | `true` | `cargo test` on the bindings crate. |
| `ty` / `ty-required` | boolean | `true` | As in `python-test.yml`. |
| `cpu-only-args` | string | `''` | A second, feature-reduced lane. **Empty skips it.** |
| `timeout-minutes` | number | `30` | |

The Python matrix defaults to the **ends** of the supported range rather than
every version in it. With `abi3-py310` one wheel covers 3.10 through 3.14, so
testing the middle proves nothing the ends don't.

`--release` is not optional on a numerics crate. A debug build of the kernels is
roughly an order of magnitude slower, and the recall assertions build real
indices.

`ty` runs against the source tree rather than an installed build, because it
reads the `.pyi` stub for the compiled module. That keeps the lint job free of a
maturin build, which is most of why it is a separate job at all. It still needs
the third-party imports resolvable, so the job runs
`uv pip install -r pyproject.toml --all-extras`, which pulls the declared
dependencies without building the project. Without it every `import numpy` is an
`unresolved-import` and the whole check is noise.

The reduced lane is the `--no-default-features` build. On `ann-search-rs` that
means CPU-only: hosted runners have no GPU adapter either way, so what it proves
is that the smaller build compiles and that `import ann_search.gpu` fails with
the message it is supposed to. Kernel correctness needs a runner with a device
and is not in scope here.

### `python-maturin-release.yml`

Same shape as `rust-release.yml`: triggered by a completed test run, not a push.

```yaml
name: Release the Python bindings
on:
  workflow_run:
    workflows: ["Test the Python bindings"]
    branches: [main]
    types: [completed]
  workflow_dispatch:
permissions:
  contents: write
  id-token: write
jobs:
  release:
    uses: GregorLueg/personal-actions/.github/workflows/python-maturin-release.yml@v1
    with:
      sdist: false
      environment: pypi
```

| input | type | default | what it does |
|---|---|---|---|
| `working-directory` | string | `python` | |
| `tag-prefix` | string | `py-v` | Prefix for the release tag. |
| `tag` | boolean | `true` | Cut the tag and the GitHub release. False plus `publish: false` is a pure build rehearsal. |
| `publish` | boolean | `true` | |
| `repository-url` | string | `''` | Point at `https://test.pypi.org/legacy/` for a rehearsal. |
| `environment` | string | `''` | GitHub environment gating the publish job. |
| `linux-target` | string | `x86_64` | |
| `manylinux` | string | `auto` | |
| `maturin-args` | string | `''` | Appended to every `maturin build`. |
| `sdist` | boolean | `false` | Also build a source distribution. |
| `timeout-minutes` | number | `45` | |

**The version comes from two files.** The distribution name is `name` in
`[project]` of `pyproject.toml` and is not the crate name (`ann-search` against
`ann-search-py`). The version is `version` in `[package]` of `Cargo.toml`,
because a maturin project declares `dynamic = ["version"]` and maturin reads it
from there. Both reads are section aware.

**`tag-prefix` defaults to `py-v` rather than `v`.** The bindings usually sit
inside the crate's own repo, where `rust-release.yml` already owns `v$version`
and the two versions move together. Two workflows racing for one tag name has a
permanent loser.

The two gates are the same independent pair as `rust-release.yml`, so a run that
dies between them is recoverable by dispatching the caller again. The build jobs
check out the release tag once there is one, so what ships is what the tag points
at even if `main` has moved on.

`uv build` is replaced by a `PyO3/maturin-action@v1` matrix: manylinux on
`ubuntu-latest`, `macos-14` for arm64 and `macos-15-intel` for x86_64, plus an
optional sdist. abi3 means one wheel per platform covers every interpreter, so
the matrix is platforms only. Artefacts upload, and a separate publish job
collects them and runs `pypa/gh-action-pypi-publish`. Publishing is its own job
so the environment gate sits on the irreversible step and nothing else.

`sdist` is off by default and deliberately so. Bindings in a subdirectory carry
a `path` dependency on the parent crate, and whether maturin vendors that into
an sdist which then builds is a matter of fact rather than opinion. Check with
`maturin sdist` and a clean `pip install dist/*.tar.gz` before turning it on. A
PyO3 project with wheels and no sdist is common; one with an sdist nobody can
build is worse.

**No `secrets: inherit` and no API token**, same as `python-release.yml`.
Trusted publishing over OIDC, so the caller needs `id-token: write` and PyPI
needs a pending publisher naming the **caller's** workflow filename, not this
one. The OIDC `workflow_ref` claim carries the top-level workflow, and getting
it wrong is the usual cause of a 403 on a first publish.

**PyPI is irreversible.** It will not accept a re-upload of a version or even of
a filename. The existence check runs before anything is built or pushed.

### `python-docs.yml`

mkdocs-material for the narrative pages, mkdocstrings for an API reference
generated out of the docstrings. The Python answer to `r-pkgdown.yml`, same
discipline: a PR builds the site to prove it builds and publishes nothing.

```yaml
name: Python docs
on:
  push:
    branches: [main]
    paths: ['python/**', '.github/workflows/python-docs.yml']
  pull_request:
    branches: [main]
    paths: ['python/**', '.github/workflows/python-docs.yml']
  workflow_dispatch:
permissions:
  contents: write
jobs:
  docs:
    uses: GregorLueg/personal-actions/.github/workflows/python-docs.yml@v1
```

| input | type | default | what it does |
|---|---|---|---|
| `working-directory` | string | `python` | Where `mkdocs.yml` lives. |
| `maturin` | boolean | `true` | Build the extension first. Off for a pure-Python package. |
| `maturin-args` | string | `--release` | |
| `docs-deps` | string | `mkdocs mkdocs-material mkdocstrings[python]` | |
| `python-version` | string | `3.12` | |
| `strict` | boolean | `true` | `mkdocs build --strict`. |
| `timeout-minutes` | number | `30` | |

The maturin step is the reason this cannot be a lint job in
`python-maturin-test.yml`: mkdocstrings imports the package to read its
docstrings, so a compiled extension has to exist first.

`--strict` is on by default. A docs job that goes green on an unresolvable
`:::` reference or a dead internal link is not doing anything.

Deploy uses `JamesIves/github-pages-deploy-action` to `gh-pages`, as
`r-pkgdown.yml` does, but leaves `clean` on. mkdocs renders the whole site every
time, so a page dropped from the nav should disappear from the branch rather
than linger as an orphan nobody can navigate to.

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

Worth knowing what that leaves untested. `cargo publish` in `rust-release.yml`
only fires on a real version bump, and the `rust: false` input on the R
workflows is set by no package. The three `python-maturin-*` and `python-docs`
workflows are new and have not run at all: nothing in them beyond actionlint has
been proven, and the wheel matrix in particular touches two things nobody here
has built before, a manylinux container compiling the wgpu stack and a maturin
sdist over a `path` dependency into a parent crate.

Land those the careful way: point `ann-search-rs`' callers at the branch
(`python-maturin-release.yml@feat/python-workflows` is valid), dispatch with
`tag: false, publish: false` until the wheels build, then rehearse against
TestPyPI, and only then move `v1`.

The publish path is worth the extra care for that reason. Before moving `v1`
after a change to `rust-release.yml`, point one consumer's caller at the branch
(`rust-release.yml@<branch>` is valid) and dispatch it, rather than deploying to
six crates on an untested path.
