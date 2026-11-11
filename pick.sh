#!/usr/bin/env bash
# Pick the next release version from the tags on stdin, one per line:
#
#   gh api --paginate repos/OWNER/REPO/tags --jq '.[].name' | VERSION=... BUMP=... pick.sh
#
# A version's tag is TAG_PREFIX followed by the version: vX.Y.Z by default. Set TAG_PREFIX to
# another prefix (say, name-v), or to empty for tags without one.
#
# VERSION, if set, is the version: X.Y.Z, or X.Y.Z-PRERELEASE when ALLOW_PRERELEASE is true, with
# or without the tag prefix. Otherwise BUMP (patch, minor or major) bumps the latest release tag,
# or 0.0.0 without one. Prerelease tags never count as the latest, and tags that are not a version
# after the tag prefix are ignored.
#
# Fails if the version's tag exists already, and, unless REQUIRE_NEWER is false, if it is not newer
# than the latest (turn it off for a patch to an older minor version, say).
#
# Writes to GITHUB_OUTPUT:
#   version=     the version, X.Y.Z (or X.Y.Z-PRERELEASE)
#   tag=         its tag, TAG_PREFIX followed by the version
#   latest=      the latest release tag, or the tag of 0.0.0 without one
#   make-latest= true when the version is a release newer than every release tag, so it should be
#                marked the Latest release (GitHub's make_latest, gh release create --latest)
#   prerelease=  true for X.Y.Z-PRERELEASE
#   previous=    the tag its release notes start at: the highest tag below it (only release tags
#                for a release, prereleases too for a prerelease); empty without one
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

# `-`, not `:-`: an empty prefix means tags without one.
prefix="${TAG_PREFIX-v}"

# A version: valid semver without a build part. semver-tool also takes a leading v, which a version
# must not have: a v belongs to the tag prefix.
is_version() {
  [[ "$1" == [0-9]* ]] &&
    [[ "$("$semver" validate "$1")" == valid ]] &&
    [[ -z "$("$semver" get build "$1")" ]]
}

# X.Y.Z, without a prerelease part.
is_release() {
  is_version "$1" && [[ -z "$("$semver" get prerel "$1")" ]]
}

latest=0.0.0 # the base for a bump when there is no release tag
found=false
tags=""
versions="" # the versions of the tags with the prefix, one per line
# `|| [[ -n $tag ]]`: also the last line when it has no newline.
while read -r tag || [[ -n "$tag" ]]; do
  tags+="$tag"$'\n'
  # Quoted: the prefix is literal, not a pattern.
  [[ "$tag" == "$prefix"* ]] || continue
  version="${tag#"$prefix"}"
  is_version "$version" || continue
  versions+="$version"$'\n'
  if is_release "$version" && { [[ $found == false ]] || [[ "$("$semver" compare "$version" "$latest")" == 1 ]]; }; then
    latest="$version"
    found=true
  fi
done

if [[ -n "$prefix" ]]; then
  forms="with or without the tag prefix, $prefix"
else
  forms="without a tag prefix"
fi

if [[ -n "${VERSION:-}" ]]; then
  next="${VERSION#"$prefix"}"
  if is_release "$next"; then
    prerelease=false
  elif [[ $allow_prerelease == true ]] && is_version "$next"; then
    prerelease=true
  elif [[ $allow_prerelease == true ]]; then
    echo "::error::version must be X.Y.Z or X.Y.Z-PRERELEASE ($forms), got: $VERSION" >&2
    exit 1
  else
    echo "::error::version must be X.Y.Z ($forms; set allow-prerelease (ALLOW_PRERELEASE) to true for X.Y.Z-PRERELEASE), got: $VERSION" >&2
    exit 1
  fi
else
  case "${BUMP:-}" in
    patch | minor | major) next="$("$semver" bump "$BUMP" "$latest")" ;;
    *)
      echo "::error::bump must be patch, minor or major, got: ${BUMP:-}" >&2
      exit 1
      ;;
  esac
  prerelease=false
fi

tag="$prefix$next"

if grep -qxF -- "$tag" <<< "$tags"; then
  echo "::error::$tag already exists" >&2
  exit 1
fi

if [[ $found == false ]] || [[ "$("$semver" compare "$next" "$latest")" == 1 ]]; then
  newer=true
else
  newer=false
  if [[ $require_newer == true ]]; then
    echo "::error::$tag is older than the latest release tag, $prefix$latest; set require-newer (REQUIRE_NEWER) to false to release it" >&2
    exit 1
  fi
fi

# A prerelease is never the Latest release.
if [[ $newer == true && $prerelease == false ]]; then make_latest=true; else make_latest=false; fi

previous=""
while read -r version; do
  [[ -n "$version" ]] || continue
  if [[ $prerelease == false ]]; then is_release "$version" || continue; fi
  if [[ "$("$semver" compare "$version" "$next")" == -1 ]] &&
    { [[ -z "$previous" ]] || [[ "$("$semver" compare "$version" "$previous")" == 1 ]]; }; then
    previous="$version"
  fi
done <<< "$versions"

previous_tag="${previous:+$prefix$previous}"

echo "Next version: $next (tag: $tag; latest: $prefix$latest; make Latest: $make_latest; prerelease: $prerelease; previous: ${previous_tag:-none})"
{
  echo "version=$next"
  echo "tag=$tag"
  echo "latest=$prefix$latest"
  echo "make-latest=$make_latest"
  echo "prerelease=$prerelease"
  echo "previous=$previous_tag"
} >> "${GITHUB_OUTPUT:-/dev/null}"
