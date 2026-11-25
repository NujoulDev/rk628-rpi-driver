#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null || fail "Install $2 to provide $1."; }
source_version() {
    git show "$1:dkms.conf" | sed -n 's/^PACKAGE_VERSION="\([^"]*\)"/\1/p'
}
check_source_version() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] \
        || fail "Unsupported driver version: $1"
}
check_package_version() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+(~(alpha|beta|rc)\.[0-9]+)?-[1-9][0-9]*$ ]] \
        || fail "Expected a version such as 0.1.1-1 or 0.1.1~rc.1-1: $1"
}

mode=${1:---dry-run}
case "$mode" in
    --prepare|--dry-run|--execute) [[ $# -le 1 ]] || fail "Too many arguments." ;;
    --verify-tag) [[ $# -eq 2 ]] || fail "--verify-tag requires a packaging tag." ;;
    --help|-h)
        echo 'Usage: ./release.sh [--prepare | --dry-run | --execute]'
        exit 0 ;;
    *) fail "Usage: ./release.sh [--prepare | --dry-run | --execute]" ;;
esac

require git git
require dpkg-parsechangelog dpkg-dev
cd "$(git rev-parse --show-toplevel)"
remote=origin
source_branch=main
recipe_branch=debian/latest

if [[ $mode != --verify-tag ]]; then
    [[ $(git branch --show-current) == "$recipe_branch" ]] \
        || fail "Run this from the debian/latest worktree."
    [[ -z $(git status --porcelain) ]] || fail "Commit or stash local changes first."
    git fetch --quiet --tags "$remote"
fi

if [[ $mode == --prepare ]]; then
    require dch devscripts
    if git show-ref --verify --quiet "refs/remotes/$remote/$recipe_branch"; then
        git merge-base --is-ancestor "$remote/$recipe_branch" HEAD \
            || fail "Update this worktree from origin/debian/latest first."
    fi
    driver_version=$(source_version "$remote/$source_branch")
    check_source_version "$driver_version"
    upstream=${driver_version//-/'~'}
    current=$(dpkg-parsechangelog -S Version)
    check_package_version "$current"
    if [[ ${current%-*} == "$upstream" ]]; then
        if ! git show-ref --verify --quiet "refs/tags/debian/${current//'~'/_}"; then
            echo "Changelog $current is already prepared. Edit its notes, commit and push."
            exit 0
        fi
        revision=${current##*-}
        next="$upstream-$((10#$revision + 1))"
    else
        next="$upstream-1"
    fi
    dpkg --compare-versions "$next" gt "$current" \
        || fail "Driver version must advance beyond $current."
    author=${DEBFULLNAME:-$(git config user.name || true)}
    email=${DEBEMAIL:-$(git config user.email || true)}
    [[ -n $author && -n $email ]] || fail "Configure git user.name and user.email first."
    DEBFULLNAME="$author" DEBEMAIL="$email" \
        dch --vendor Debian --newversion "$next" --distribution unstable \
        'EDIT ME: describe the changes for this release.'
    echo "Prepared $next. Replace EDIT ME, commit, push and wait for CI."
    exit 0
fi

require gh gh
require sha256sum coreutils
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
recipe_sha=$(git rev-parse HEAD)
if [[ $mode != --verify-tag ]]; then
    [[ $recipe_sha == "$(git rev-parse "$remote/$recipe_branch")" ]] \
        || fail "Push this packaging commit to origin/debian/latest first."
fi

git merge-base --is-ancestor "$recipe_sha" "$remote/$recipe_branch" \
    || fail "Packaging commit is not on origin/debian/latest."
package=$(dpkg-parsechangelog -S Source)
version=$(dpkg-parsechangelog -S Version)
check_package_version "$version"
upstream=${version%-*}
source_tag="v${upstream//'~'/-}"
recipe_tag="debian/${version//'~'/_}"
notes=$(dpkg-parsechangelog -S Changes)
[[ $notes != *'EDIT ME'* ]] || fail "Replace EDIT ME in debian/changelog first."

if [[ $mode == --verify-tag ]]; then
    [[ $2 == "$recipe_tag" ]] || fail "Tag $2 does not match changelog $version."
    [[ $(git rev-parse "refs/tags/$recipe_tag^{commit}") == "$recipe_sha" ]] \
        || fail "Packaging tag points to a different commit."
fi

create_source=true
if git show-ref --verify --quiet "refs/tags/$source_tag"; then
    source_sha=$(git rev-parse "refs/tags/$source_tag^{commit}")
    create_source=false
else
    [[ $mode != --verify-tag ]] || fail "Missing source tag: $source_tag"
    source_sha=$(git rev-parse "$remote/$source_branch")
fi

git merge-base --is-ancestor "$source_sha" "$remote/$source_branch" \
    || fail "Source commit is not on origin/main."
driver_version=$(source_version "$source_sha")
check_source_version "$driver_version"
[[ ${driver_version//-/'~'} == "$upstream" ]] \
    || fail "Source PACKAGE_VERSION $driver_version does not match changelog $version."
if git show-ref --verify --quiet "refs/tags/$recipe_tag"; then
    [[ $(git rev-parse "refs/tags/$recipe_tag^{commit}") == "$recipe_sha" ]] \
        || fail "$recipe_tag already names another commit. Prepare a new package revision."
fi

# A successful run must cover exactly the commit being released.
ci_run() {
    local workflow=$1 sha=$2 branch=$3 record run_id actual_sha status conclusion
    record=$(gh api --method GET "repos/$repo/actions/workflows/$workflow/runs" \
        -f "head_sha=$sha" -f "branch=$branch" -f per_page=10 \
        --jq '[.workflow_runs[] | select(.event == "push" or .event == "workflow_dispatch")][0] | select(. != null) | [.id, .head_sha, .status, .conclusion] | @tsv')
    [[ -n $record ]] || fail "No $workflow run found for $sha."
    IFS=$'\t' read -r run_id actual_sha status conclusion <<< "$record"
    [[ $run_id =~ ^[0-9]+$ && $actual_sha == "$sha" && $status == completed && $conclusion == success ]] \
        || fail "$workflow for $sha is not successfully completed."
    printf '%s\n' "$run_id"
}

source_run=$(ci_run build.yml "$source_sha" "$source_branch")
recipe_run=$(ci_run ci.yml "$recipe_sha" "$recipe_branch")
artifact="${package}_${version}"
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
gh run download "$recipe_run" --repo "$repo" --name "$artifact" --dir "$temporary/ci"
for field in "Package: $package" "Version: $version" \
    "Source commit: $source_sha" "Recipe commit: $recipe_sha"; do
    grep -Fxq "$field" "$temporary/ci/BUILD-INFO.txt" \
        || fail "Packaging CI did not build this source/recipe pair. Rerun CI for the correct source; use a new driver version when an existing source tag names older code."
done
(cd "$temporary/ci" && sha256sum --check SHA256SUMS)

printf 'Package: %s %s\nSource: %s -> %s\nRecipe: %s -> %s\nCI runs: source %s, packaging %s\n' \
    "$package" "$version" "$source_tag" "$source_sha" "$recipe_tag" "$recipe_sha" "$source_run" "$recipe_run"

if [[ $mode == --verify-tag ]]; then
    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required for workflow validation}"
    {
        echo "package=$package"
        echo "version=$version"
        echo "source-tag=$source_tag"
        echo "source-sha=$source_sha"
        echo "recipe-sha=$recipe_sha"
        echo "artifact=$artifact"
    } >> "$GITHUB_OUTPUT"
    exit 0
fi

if [[ $mode == --dry-run ]]; then
    echo 'Dry run complete. Use --execute to create and push the release tags.'
    exit 0
fi
read -r -p 'Push these release tags? [y/N] ' answer
[[ $answer == y || $answer == Y ]] || { echo 'Cancelled.'; exit 0; }
if [[ $create_source == true ]]; then
    git tag -a "$source_tag" "$source_sha" -m "$package $driver_version"
fi
if ! git show-ref --verify --quiet "refs/tags/$recipe_tag"; then
    git tag -a "$recipe_tag" "$recipe_sha" -m "$package $version"
fi
git push --atomic "$remote" "refs/tags/$source_tag" "refs/tags/$recipe_tag"
echo "Tags pushed. Watch https://github.com/$repo/actions for the release draft."
