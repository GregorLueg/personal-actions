# `python-docs.yml`

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
