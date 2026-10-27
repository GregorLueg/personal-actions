# `r-cran-check.yml`

Checks the tarball you'd actually upload to CRAN: vendored crates, vignettes
built, `NOT_CRAN` unset, `--as-cran`, on R release and devel. `r-cmd-check.yml`
answers "does it work", this one answers "will CRAN take it". Dispatch it before
a submission rather than on every push.

```yaml
name: CRAN check
on:
  workflow_dispatch:
jobs:
  cran-check:
    uses: GregorLueg/personal-actions/.github/workflows/r-cran-check.yml@v1
    with:
      msrv: 1.90.0
    secrets: inherit
```

| input | type | default | what it does |
|---|---|---|---|
| `vendor-script` | string | `tools/vendor.sh` | Script, relative to the package root, that writes `src/rust/vendor.tar.xz`. Empty for a package without Rust. |
| `msrv` | string | `''` | Extra Linux lane on this rustc. Match the floor in `SystemRequirements`: CRAN's Linux machines use the distro rustc, which lags stable. Empty skips the lane. |
| `max-tarball-mb` | number | `10` | Fail the build above this size. CRAN asks for 10 MB unless you request more at submission. |
| `extra-sysdeps` | string | `''` | Extra apt packages, space separated. |

One job runs `R CMD build` and uploads the tarball. Every check lane then runs
on that tarball, not on the checkout: Linux release and devel, macOS release,
Windows release and devel, plus the `msrv` lane if set. Any `WARNING` or
`ERROR` in the status line fails the lane. NOTEs don't, read them yourself.

No sccache and none of the LTO overrides `r-cmd-check.yml` sets, so the
install log and timings are what CRAN sees.

`NOT_CRAN` stays unset on purpose. With it set, `tools/config.R` drops
`--offline` and the vendored path never runs. A dedicated step then greps the
install log for "Using offline vendor tarball" and fails if it's missing, so a
build that quietly went online can't pass.

The PDF manual is built on Linux only, where TinyTeX plus `makeindex` is
installed (`tlmgr` updates itself first, or every install dies once CTAN ships
a newer `tlmgr`). R CMD check's "LaTeX errors found" lists nothing useful, so on
failure the job reruns `pdflatex` and `Rd2pdf` on the leftover `.tex` and
prints the actual error.

Every lane uploads its `*.Rcheck/00*` logs as an artefact, pass or fail.
