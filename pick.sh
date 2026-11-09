#!/usr/bin/env bash
# Pick the next release version from the tags on stdin, one per line:
#
#   gh api --paginate repos/OWNER/REPO/tags --jq '.[].name' | VERSION=... BUMP=... pick.sh
#
# VERSION, if set, is the version: vX.Y.Z, or vX.Y.Z-PRERELEASE when ALLOW_PRERELEASE is true.
# Otherwise BUMP (patch, minor or major) bumps the latest vX.Y.Z tag, or v0.0.0 without one.
# Prerelease tags never count as the latest, and tags that are not versions are ignored.
#
# Fails if the version is already a tag, and, unless REQUIRE_NEWER is false, if it is not newer
# than the latest (turn it off for a patch to an older minor version, say).
#
# Writes to GITHUB_OUTPUT:
#   version=     the version
#   latest=      the latest vX.Y.Z tag, or v0.0.0 without one
#   make-latest= true when the version is a release newer than every vX.Y.Z tag, so it should be
#                marked the Latest release (GitHub's make_latest, gh release create --latest)
#   prerelease=  true for vX.Y.Z-PRERELEASE
#   previous=    where its release notes start: the highest tag below it (only vX.Y.Z tags for a
#                release, prereleases too for a prerelease); empty without one
set -euo pipefail

semver="$(dirname "${BASH_SOURCE[0]}")/semver"

# flag NAME DEFAULT: the value of the true/false environment variable NAME, DEFAULT when unset or
# empty
flag() {
  local value="${!1:-$2}"
  case "$value" in
    true | false) echo "$value" ;;
    *)
      echo "::error::$(tr 'A-Z_' 'a-z-' <<< "$1") ($1) must be true or false, got: $value" >&2
      exit 1
      ;;
  esac
}

require_newer="$(flag REQUIRE_NEWER true)"
allow_prerelease="$(flag ALLOW_PRERELEASE false)"

# A tag-shaped version: valid semver with the lowercase v, without a build part.
is_version() {
  [[ "$1" == v* ]] &&
    [[ "$("$semver" validate "$1")" == valid ]] &&
    [[ -z "$("$semver" get build "$1")" ]]
}

# vX.Y.Z, without a prerelease part.
is_release() {
  is_version "$1" && [[ -z "$("$semver" get prerel "$1")" ]]
}

latest=v0.0.0 # the base for a bump when there is no vX.Y.Z tag
found=false
tags=""
# `|| [[ -n $tag ]]`: also the last line when it has no newline.
while read -r tag || [[ -n "$tag" ]]; do
  tags+="$tag"$'\n'
  if is_release "$tag" && { [[ $found == false ]] || [[ "$("$semver" compare "$tag" "$latest")" == 1 ]]; }; then
    latest="$tag"
    found=true
  fi
done

if [[ -n "${VERSION:-}" ]]; then
  if is_release "$VERSION"; then
    prerelease=false
  elif [[ $allow_prerelease == true ]] && is_version "$VERSION"; then
    prerelease=true
  elif [[ $allow_prerelease == true ]]; then
    echo "::error::version must be vX.Y.Z or vX.Y.Z-PRERELEASE, got: $VERSION" >&2
    exit 1
  else
    echo "::error::version must be vX.Y.Z (set allow-prerelease (ALLOW_PRERELEASE) to true for vX.Y.Z-PRERELEASE), got: $VERSION" >&2
    exit 1
  fi
  next="$VERSION"
else
  case "${BUMP:-}" in
    patch | minor | major) next="v$("$semver" bump "$BUMP" "$latest")" ;;
    *)
      echo "::error::bump must be patch, minor or major, got: ${BUMP:-}" >&2
      exit 1
      ;;
  esac
  prerelease=false
fi

if grep -qxF -- "$next" <<< "$tags"; then
  echo "::error::$next already exists" >&2
  exit 1
fi

if [[ $found == false ]] || [[ "$("$semver" compare "$next" "$latest")" == 1 ]]; then
  newer=true
else
  newer=false
  if [[ $require_newer == true ]]; then
    echo "::error::$next is older than the latest release tag, $latest; set require-newer (REQUIRE_NEWER) to false to release it" >&2
    exit 1
  fi
fi

# A prerelease is never the Latest release.
if [[ $newer == true && $prerelease == false ]]; then make_latest=true; else make_latest=false; fi

previous=""
while read -r tag; do
  if [[ $prerelease == true ]]; then is_version "$tag" || continue; else is_release "$tag" || continue; fi
  if [[ "$("$semver" compare "$tag" "$next")" == -1 ]] &&
    { [[ -z "$previous" ]] || [[ "$("$semver" compare "$tag" "$previous")" == 1 ]]; }; then
    previous="$tag"
  fi
done <<< "$tags"

echo "Next version: $next (latest: $latest; make Latest: $make_latest; prerelease: $prerelease; previous: ${previous:-none})"
{
  echo "version=$next"
  echo "latest=$latest"
  echo "make-latest=$make_latest"
  echo "prerelease=$prerelease"
  echo "previous=$previous"
} >> "${GITHUB_OUTPUT:-/dev/null}"
