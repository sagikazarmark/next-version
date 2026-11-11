# next-version

GitHub Action that picks the next version from a repository's tags. It bumps the latest `vX.Y.Z`
tag by `patch`, `minor` or `major`, or checks an exact version you pass. It refuses a version that
is already a tag, and by default one that is not newer than the latest.

It reads the tags through the GitHub API, so it needs no checkout and no `fetch-depth: 0`.

## Usage

```yaml
on:
  workflow_dispatch:
    inputs:
      bump:
        type: choice
        options: [patch, minor, major]
        default: patch
      version:
        description: Exact version, X.Y.Z (overrides bump)
        type: string

jobs:
  release:
    runs-on: ubuntu-latest

    permissions:
      contents: write

    steps:
      - name: Pick the version
        id: version
        uses: sagikazarmark/next-version@v1
        with:
          bump: ${{ inputs.bump }}
          version: ${{ inputs.version }}

      - name: Release
        env:
          GH_TOKEN: ${{ github.token }}
          TAG: ${{ steps.version.outputs.tag }}
        run: gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --generate-notes
```

The `version` output is the version alone (`1.2.3`), for a manifest or a package registry; the
`tag` output is its tag (`v1.2.3`).

The first release counts from `0.0.0`, so `patch` gives `0.0.1`. Pass `version: 0.1.0` (or any
other) to start elsewhere. An exact version may have the tag prefix or not: `v0.1.0` and `0.1.0` are
the same version. A version as it is never loses a prefix, so with a prefix that ends in a digit,
say `1`, `11.2.3` is version `11.2.3`, not `1.2.3`.

### Which tags count

Only tags of the form `vX.Y.Z` count as releases: `v` in lowercase, no leading zeros, no
prerelease or build part. The latest release is the highest of them by
[semantic versioning](https://semver.org), not the most recent or the last alphabetically.
Prerelease tags (`v1.0.0-rc.1`) never count as the latest, and other tags are ignored. Every tag,
of whatever form, counts when checking that the version does not exist yet.

### Another tag prefix

`tag-prefix` is what comes before the version in a tag, `v` by default. Set it for the tags of one
package in a repository that releases several (`name-vX.Y.Z`), or to empty for tags without a
prefix (`X.Y.Z`):

```yaml
- uses: sagikazarmark/next-version@v1
  id: version
  with:
    bump: minor
    tag-prefix: name-v
```

Only tags with the prefix count: with `name-v`, `name-v1.2.0` is version `1.2.0`, while `v1.3.0`
and `other-v1.4.0` are ignored. The prefix is literal text, not a pattern. The `tag`, `latest` and
`previous` outputs carry it; `version` does not.

### Release an older version

A patch to an older minor version, say `v1.4.3` after `v1.5.0`, is older than the latest. Allow it
with `require-newer: false`:

```yaml
- uses: sagikazarmark/next-version@v1
  id: version
  with:
    version: v1.4.3
    require-newer: false
```

It still must not exist. Publish it without marking it the Latest release, so that tools following
the latest release stay on `v1.5.0`, and start its release notes at the version before it:

```sh
gh release create "$TAG" --latest="$MAKE_LATEST" --notes-start-tag "$PREVIOUS" --generate-notes
```

with `TAG`, `MAKE_LATEST` and `PREVIOUS` set from the `tag`, `make-latest` and `previous` outputs.
`previous` is empty when there is no older version; drop `--notes-start-tag` then.

### Release a prerelease

Exact versions may have a prerelease part with `allow-prerelease: true`:

```yaml
- uses: sagikazarmark/next-version@v1
  id: version
  with:
    version: v2.0.0-rc.1
    allow-prerelease: true
```

Bumps always give a release, never a prerelease. A prerelease must be newer than the latest
release (so `v1.5.0-rc.1` after `v1.5.0` fails unless `require-newer` is false), and its
`make-latest` output is always `false`; publish it with `gh release create --prerelease`. Its
`previous` output includes prereleases, so the notes for `v2.0.0-rc.2` start at `v2.0.0-rc.1`,
while those for `v2.0.0` start at the release before it.

## Inputs

| Name | Description | Default |
| --- | --- | --- |
| `bump` | `patch`, `minor` or `major`. Ignored when `version` is set. | `patch` |
| `version` | Exact version, `X.Y.Z` (or `X.Y.Z-PRERELEASE` with `allow-prerelease`), with or without the tag prefix. Overrides `bump`. | `""` |
| `tag-prefix` | What comes before the version in a tag. Only tags with it count. Empty for tags without a prefix. | `v` |
| `require-newer` | Require the version to be newer than the latest release tag. | `true` |
| `allow-prerelease` | Allow an exact version with a prerelease part. | `false` |
| `repository` | The repository whose tags to read, `owner/name`. | The current repository |
| `token` | Token for reading the tags. | `github.token` |

## Outputs

| Name | Description |
| --- | --- |
| `version` | The version, without the tag prefix: `1.2.3`. |
| `tag` | The version's tag, the tag prefix followed by the version: `v1.2.3`. |
| `latest` | The latest release tag, or the tag of `0.0.0` (`v0.0.0`) without one. |
| `make-latest` | `true` when the version is a release newer than every release tag, so it should be marked the Latest release (`gh release create --latest`, the API's `make_latest`). |
| `prerelease` | `true` when the version has a prerelease part. |
| `previous` | The tag its release notes start at: the highest tag below the version (only release tags for a release, prereleases too for a prerelease). Empty without one. |

## Run it locally

`pick.sh` reads the tags from stdin, one per line, and takes the inputs as environment variables
(`BUMP`, `VERSION`, `TAG_PREFIX`, `REQUIRE_NEWER`, `ALLOW_PRERELEASE`). `TAG_PREFIX` is `v` when
unset; set it to empty for tags without a prefix:

```sh
git tag --list | BUMP=minor ./pick.sh
gh api --paginate repos/OWNER/REPO/tags --jq '.[].name' | VERSION=v1.4.3 REQUIRE_NEWER=false ./pick.sh
```

It prints the result, and writes the outputs to `$GITHUB_OUTPUT` when that is set. Run the tests
with `./pick_test.sh`; they need only bash (3.2 or newer).

## License

`semver` is [semver-tool](https://github.com/fsaintjacques/semver-tool) 3.4.0, vendored unmodified
and licensed under the
[Apache License 2.0](https://github.com/fsaintjacques/semver-tool/blob/3.4.0/LICENSE).
