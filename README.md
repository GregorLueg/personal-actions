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
| [`r-cmd-check.yml`](docs/r-cmd-check.md) | R CMD check, with or without a Rust crate |
| [`r-cran-check.yml`](docs/r-cran-check.md) | `--as-cran` on the vendored tarball, release and devel, before a submission |
| [`r-pkgdown.yml`](docs/r-pkgdown.md) | Build the pkgdown site, deploy on non-PR events |
| [`r-auto-tag.yml`](docs/r-auto-tag.md) | Tag and release on a version bump, gated on a green check |
| [`r-conda-release.yml`](docs/r-conda-release.md) | Build a conda package with rattler-build and publish it to a prefix.dev channel |
| [`rust-test.yml`](docs/rust-test.md) | Crate tests, CPU and GPU lanes |
| [`rust-release.yml`](docs/rust-release.md) | Tag, release and `cargo publish`, gated on a green test |
| [`rust-binary-release.yml`](docs/rust-binary-release.md) | Build a CLI binary per platform and attach it to that release |
| [`rust-workspace-test.yml`](docs/rust-workspace-test.md) | Workspace tests: per-member check, CPU, R and GPU lanes |
| [`rust-workspace-release.yml`](docs/rust-workspace-release.md) | One tag, one `cargo publish` per member in dependency order |
| [`python-test.yml`](docs/python-test.md) | ruff, ty and pytest over an OS x interpreter matrix |
| [`python-release.yml`](docs/python-release.md) | Tag, release and `uv publish`, gated on a green test |
| [`python-maturin-test.yml`](docs/python-maturin-test.md) | The same, plus cargo, for a PyO3 extension |
| [`python-maturin-release.yml`](docs/python-maturin-release.md) | Tag, release and a per-platform wheel matrix; the caller uploads |
| [`python-docs.yml`](docs/python-docs.md) | Build the mkdocs site, deploy on non-PR events |

**Two Python pairs, not one.** The `python-*` pair is for a pure-Python uv
project: `uv sync`, `uv lock --check`, `uv build`. The `python-maturin-*` pair
is for a PyO3 extension, which has a cargo workspace, no uv lockfile, a compile
step between install and test, and needs a wheel per platform rather than the
one `uv build` produces for whatever runner it lands on. Neither is a superset
of the other, which is why they are separate files rather than a pile of inputs
on one.

Consumers: five R packages, six Rust crates and two Python packages
(`ann-search-rs` is the maturin one).
`node2vec-rs` uses `rust-test.yml` but keeps a bespoke release, which
predates `rust-binary-release.yml` and can move onto it.

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
workflows is set by no package. `uv publish` in `python-release.yml` has never
run, and see the warning in
[its doc](docs/python-release.md): it is likely broken for the same
reason `python-maturin-release.yml` was.

`python-maturin-test.yml`, `python-docs.yml` and the build half of
`python-maturin-release.yml` have now run in anger on `ann-search-rs`, wheels
included. Two things they taught, both of which cost a full wheel matrix to
discover:

- A dependency that builds fine on macOS arm64 can be impossible on manylinux.
  The CubeCL `cpu` feature pulls a prebuilt LLVM needing glibc 2.33+.
- PyPI cannot name a reusable workflow as a trusted publisher, so the upload has
  to run in the caller.

The `sdist` path over a `path` dependency into a parent crate is still
unexercised, which is why it defaults to off.

Land those the careful way: point `ann-search-rs`' callers at the branch
(`python-maturin-release.yml@feat/python-workflows` is valid), dispatch with
`tag: false, publish: false` until the wheels build, then rehearse against
TestPyPI, and only then move `v1`.

The publish path is worth the extra care for that reason. Before moving `v1`
after a change to `rust-release.yml`, point one consumer's caller at the branch
(`rust-release.yml@<branch>` is valid) and dispatch it, rather than deploying to
six crates on an untested path.
