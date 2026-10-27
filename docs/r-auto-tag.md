# `r-auto-tag.yml`

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

Two outputs: `created` is `'true'` when this run cut the tag, and `tag` is the
tag read from `DESCRIPTION`, e.g. `v0.5.0`. They exist to chain
[`r-conda-release.yml`](r-conda-release.md).
