#!/usr/bin/env bash
# Cut a v1.x.y release from main and move the floating v1 tag onto it.
# Usage: scripts/release-v1.sh 1.12.0
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <1.x.y>   (latest: $(git tag -l 'v1.*' --sort=-v:refname | head -1))" >&2
  exit 1
fi

tag="v${1#v}"
[[ "$tag" =~ ^v1\.[0-9]+\.[0-9]+$ ]] || { echo "not a v1.x.y version: $tag" >&2; exit 1; }

git fetch --tags origin
[[ "$(git branch --show-current)" == main ]] || { echo "checkout main first" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean" >&2; exit 1; }
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main differs from origin/main, pull first" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "$tag already exists" >&2; exit 1; }

git tag -a "$tag" -m "$tag"
git push origin "$tag"
gh release create "$tag" --generate-notes --title "$tag"

# consumers pin @v1, so this is the step that actually ships the change
git tag -f v1 "$tag^{commit}"
git push -f origin v1

echo "released $tag, v1 -> $(git rev-parse --short v1)"
