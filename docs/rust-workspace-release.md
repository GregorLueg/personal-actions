# `rust-workspace-release.yml`

The workspace sibling of [`rust-release.yml`](rust-release.md). Every publishable member shares
one version through `[workspace.package]`.

```yaml
jobs:
  release:
    uses: GregorLueg/personal-actions/.github/workflows/rust-workspace-release.yml@v1
    with:
      needs-r: true
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `publish-args` | string | `''` | Appended to every `cargo publish -p <member>`. |
| `needs-r` | boolean | `false` | A member's publish verification build needs R. |
| `python-owns-latest` | boolean | `false` | As in [`rust-release.yml`](rust-release.md). |
| `rate-limit-max-wait-minutes` | number | `10` | Longest single wait on a crates.io 429 before the job gives up. |
| `timeout-minutes` | number | `90` | Each member is verified with its own build. Bounds the 429 waits too. |

It reads the members and the version from `cargo metadata`, fails if members
disagree on the version, and orders the publishable ones (`publish = false`
is skipped) topologically over their path dependencies, dev dependencies
included: publish verification resolves those too, so a member cannot go up
before a sibling it only tests against.

The tag and release work as in `rust-release.yml`: one `v$version` tag for the
whole workspace. crates.io rate-limits brand-new crate names, and a first
release of several members hits it. On a 429 the job reads the "try again
after" time out of the error, sleeps until then and retries that member, unless
the wait is longer than `rate-limit-max-wait-minutes`. The crates.io check runs
per member, so a run that dies anyway (a wait too long, a network error)
resumes where it stopped on rerun, and the step summary lists what was missing
and what this run published. The token in `CARGO_REGISTRY_TOKEN` needs the `publish-new`
scope the first time a member name appears.
