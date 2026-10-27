# `python-maturin-test.yml`

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
| `ty` / `ty-required` | boolean | `true` | As in [`python-test.yml`](python-test.md). |
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
