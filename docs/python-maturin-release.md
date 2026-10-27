# `python-maturin-release.yml`

Same shape as [`rust-release.yml`](rust-release.md): triggered by a completed test run, not a push.
It builds and tags. **It does not upload.**

**PyPI cannot name a reusable workflow as a trusted publisher.** The OIDC token
carries `job_workflow_ref`, which for a reusable workflow points at this
repository, and the publisher form has no field that can express that. It is a
documented limitation, [pypi/warehouse#11096]. Configuring the form with the
caller's filename does not help, because that is `workflow_ref`, a different
claim. The failure is `invalid-publisher: valid token, but no corresponding
publisher`, arriving after a full wheel matrix has been built.

So the upload lives in the calling repository, where `job_workflow_ref` is the
caller's own workflow and PyPI can match it. This workflow stops at artefacts
named `dist-*` and exposes `should-build` so the caller knows whether there is
anything to upload.

[pypi/warehouse#11096]: https://github.com/pypi/warehouse/issues/11096

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
  build:
    uses: GregorLueg/personal-actions/.github/workflows/python-maturin-release.yml@v1
    with:
      sdist: false

  publish:
    needs: build
    if: needs.build.outputs.should-build == 'true'
    runs-on: ubuntu-latest
    environment: pypi
    permissions:
      id-token: write
    steps:
      - uses: actions/download-artifact@v4
        with:
          pattern: dist-*
          merge-multiple: true
          path: dist
      - uses: pypa/gh-action-pypi-publish@release/v1
        with:
          packages-dir: dist
```

The trusted publisher on PyPI then names the **caller**: owner, the calling
repo, the caller's workflow filename, and the environment the publish job runs
in if it uses one.

| input | type | default | what it does |
|---|---|---|---|
| `working-directory` | string | `python` | |
| `tag-prefix` | string | `py-v` | Prefix for the release tag. |
| `tag` | boolean | `true` | Cut the tag and the GitHub release. |
| `publish` | boolean | `true` | Check the index first and skip the wheel matrix when the version is already there. It does not upload. |
| `repository-url` | string | `''` | Which index the version check consults. `https://test.pypi.org/legacy/` skips the check. |
| `linux-target` | string | `x86_64` | |
| `manylinux` | string | `auto` | |
| `maturin-args` | string | `''` | Appended to every `maturin build`. |
| `sdist` | boolean | `false` | Also build a source distribution. |
| `timeout-minutes` | number | `45` | |

| output | what it is |
|---|---|
| `should-build` | False when the version is already on the index, so nothing was built. **Gate the caller's publish job on this.** |
| `name` / `version` / `tag` | Read from the manifests, for a caller that wants to report them. |

**The version comes from two files.** The distribution name is `name` in
`[project]` of `pyproject.toml` and is not the crate name (`ann-search` against
`ann-search-py`). The version is `version` in `[package]` of `Cargo.toml`,
because a maturin project declares `dynamic = ["version"]` and maturin reads it
from there. Both reads are section aware.

**`tag-prefix` defaults to `py-v` rather than `v`.** The bindings usually sit
inside the crate's own repo, where `rust-release.yml` already owns `v$version`
and the two versions move independently. Two workflows racing for one tag name
has a permanent loser.

The two gates are the same independent pair as `rust-release.yml`, so a run that
dies between them is recoverable by dispatching the caller again. The build jobs
check out the release tag once there is one, so what ships is what the tag points
at even if `main` has moved on.

Wheels come from a `PyO3/maturin-action@v1` matrix: manylinux on
`ubuntu-latest`, `macos-14` for arm64 and `macos-15-intel` for x86_64, plus an
optional sdist. abi3 means one wheel per platform covers every interpreter, so
the matrix is platforms only.

**Do not put the CubeCL `cpu` feature in a wheel.** It pulls
`tracel-llvm-bundler`, a prebuilt LLVM needing glibc 2.33+, and no manylinux
container can load it. `ann-search-rs` hit this and moved it behind a test-only
feature. The symptom is `llvm-config: GLIBC_2.33 not found` in the Linux job
while macOS arm64 passes, which makes it look platform-specific rather than
like a dependency that should never have shipped.

`sdist` is off by default and deliberately so. Bindings in a subdirectory carry
a `path` dependency on the parent crate, and whether maturin vendors that into
an sdist which then builds is a matter of fact rather than opinion. Check with
`maturin sdist` and a clean `pip install dist/*.tar.gz` before turning it on. A
PyO3 project with wheels and no sdist is common; one with an sdist nobody can
build is worse.

**PyPI is irreversible.** It will not accept a re-upload of a version or even of
a filename. The existence check runs before anything is built or pushed.
