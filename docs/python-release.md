# `python-release.yml`

Same shape as [`rust-release.yml`](rust-release.md): triggered by a completed test run, not a push.

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
`--trusted-publishing always` rather than `automatic`, so a missing OIDC token
is an error instead of a silent fallback to a token that does not exist.

> **Untested, and probably broken.** This workflow runs `uv publish` inside a
> reusable workflow, which is exactly the arrangement PyPI cannot express as a
> trusted publisher: the token's `job_workflow_ref` names this repository and
> the publisher form has no field for it ([pypi/warehouse#11096]). Nobody has
> taken this path to a first publish, so it has never surfaced.
> `python-maturin-release.yml` hit it and was restructured to hand the upload
> back to the caller. This one wants the same treatment before it is used in
> anger: expose the version gate as an output and let the caller run
> `gh-action-pypi-publish` itself.

[pypi/warehouse#11096]: https://github.com/pypi/warehouse/issues/11096

**`uv publish` is irreversible.** PyPI will not accept a re-upload of a version
or even of a filename, so the PyPI check is the only thing standing between a
merge and a permanent mistake. It runs before anything is pushed anywhere.
