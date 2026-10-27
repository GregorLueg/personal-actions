# `r-conda-release.yml`

Builds a conda package with rattler-build and publishes it to a prefix.dev
channel via trusted publishing, so there's no API key anywhere. The recipe isn't
committed: `devforge::conda_recipe()` generates it from the `DESCRIPTION` at
`ref`. Backfilling an old version is dispatching with its tag.

The catch: a tag or release pushed with `GITHUB_TOKEN` starts no workflows, so
`on: release` never fires. A dispatch does. So the caller is
`workflow_dispatch` only, and the auto-tag caller dispatches it:

```yaml
name: Conda release
on:
  workflow_dispatch:
    inputs:
      ref:
        description: Tag to build, e.g. v0.5.0
        required: true
        type: string
      publish:
        description: Upload to the channel
        type: boolean
        default: true
permissions:
  contents: read
  id-token: write
jobs:
  conda:
    uses: GregorLueg/personal-actions/.github/workflows/r-conda-release.yml@v1
    with:
      channel: https://prefix.dev/gregorlueg/bixverse
      ref: ${{ inputs.ref }}
      publish: ${{ inputs.publish }}
```

and in the auto-tag caller, add `actions: write` to its permissions plus:

```yaml
  conda:
    needs: tag
    if: needs.tag.outputs.created == 'true'
    runs-on: ubuntu-latest
    steps:
      - name: Dispatch the conda release
        run: gh workflow run conda-release.yml -R "$GITHUB_REPOSITORY" -f ref="${{ needs.tag.outputs.tag }}"
        env:
          GH_TOKEN: ${{ github.token }}
```

| input | type | default | what it does |
|---|---|---|---|
| `channel` | string | required | Channel URL to publish to. Also resolves sibling packages, so a package depending on another of mine finds it there. |
| `ref` | string | `''` | Git ref to build, normally the tag. Empty builds the triggering sha. |
| `r-versions` | string | `'4.4,4.5'` | `r_base` variants, comma separated. Follow conda-forge's pinning. Ignored for a noarch package. |
| `extra-channels` | string | `''` | Further channels to resolve from, space separated, e.g. `bioconda`. `conda-forge` is always on. |
| `publish` | boolean | `true` | Off for a dry run that only builds. |
| `rattler-build-version` | string | `v0.79.0` | |

Register the **caller's** workflow file (`conda-release.yml` above) as the
trusted publisher on the channel, not this one. Renaming the caller breaks
publishing.

A pure R package comes out `noarch` and builds once on Linux. A package with a
Rust crate builds per R version on `linux-64` and `osx-arm64`. Windows is
skipped: conda's R there is built with m2w64, and making extendr's gnu toolchain
link against it isn't worth the fight.

Re-dispatching is safe. `--skip-existing=all` checks the channel too, so a tag
that's already published builds nothing and the publish step exits clean.
