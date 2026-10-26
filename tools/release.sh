#!/bin/sh
# Release: finalize the CHANGELOG heading, push main, wait for CI, tag, push the tag, wait for the release workflow.
#   tools/release.sh vX.Y.Z
# Needs: gh (logged in), a clean working tree, a "## vX.Y.Z" or "## vX.Y.Z (unreleased)" section in CHANGELOG.md.
set -e
cd "$(dirname "$0")/.."
V=$1; case "$V" in v[0-9]*.[0-9]*.[0-9]*) ;; *) echo "usage: tools/release.sh vX.Y.Z" >&2; exit 2 ;; esac
[ -z "$(git status --porcelain)" ] || { echo "release: working tree not clean" >&2; exit 1; }
grep -q "^## $V" CHANGELOG.md || { echo "release: no '## $V' section in CHANGELOG.md" >&2; exit 1; }
git rev-parse "$V" >/dev/null 2>&1 && { echo "release: tag $V already exists" >&2; exit 1; }
if grep -q "^## $V (unreleased)" CHANGELOG.md; then
  sed -i "s/^## $V (unreleased)\$/## $V/" CHANGELOG.md
  git add CHANGELOG.md && git commit -q -m "$V: finalize changelog" && echo "changelog heading finalized"
fi
tools/check-public.sh >/dev/null && echo "leak check clean"
git push origin main
sha=$(git rev-parse --short HEAD)
echo "waiting for CI on $sha ..."
i=0
while :; do
  r=$(gh run list --branch main --limit 3 --workflow ci.yml --json status,conclusion,headSha --jq ".[] | select(.headSha|startswith(\"$sha\")) | \"\(.status) \(.conclusion)\"" 2>/dev/null | head -1)
  case "$r" in
    "completed success") echo "CI green"; break ;;
    completed*) echo "release: CI failed ($r): $(gh run list --branch main --limit 1 --workflow ci.yml --json url --jq '.[0].url')" >&2; exit 1 ;;
  esac
  i=$((i + 15)); [ $i -gt 1800 ] && { echo "release: CI took too long" >&2; exit 1; }
  sleep 15
done
git tag -a "$V" -m "$V" && git push origin "$V"
echo "tag pushed, waiting for the release workflow ..."
i=0
while :; do
  r=$(gh run list --workflow release.yml --limit 1 --json status,conclusion,headBranch --jq '.[] | "\(.headBranch) \(.status) \(.conclusion)"' 2>/dev/null)
  case "$r" in
    "$V completed success") break ;;
    "$V completed"*) echo "release: workflow failed: $(gh run list --workflow release.yml --limit 1 --json url --jq '.[0].url')" >&2; exit 1 ;;
  esac
  i=$((i + 15)); [ $i -gt 1800 ] && { echo "release: workflow took too long" >&2; exit 1; }
  sleep 15
done
gh release view "$V" --json url,assets --jq '.url, (.assets[].name)'
