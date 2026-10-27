# `python-test.yml`

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
