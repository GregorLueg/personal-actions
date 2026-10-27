# `r-pkgdown.yml`

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

Inputs are `rust`, `gpu`, `extra-repositories` and `extra-sysdeps`, same meaning as in
[`r-cmd-check.yml`](r-cmd-check.md). The deploy
step is guarded by `github.event_name != 'pull_request'`, so a PR builds the
site to prove it builds and publishes nothing.
