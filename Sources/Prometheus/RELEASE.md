# Releasing 

## Release schedule

Releases of this library are performed on a when-needed basis. 

Generally one of the maintainers listed in MAINTAINERS.md will perform a release.

If you would like to request a release since a change or fix has been waiting for a release for some time,
you may open up an issue on github, requesting a release.

## Versioning 

As usual with Swift packages, we use [Semantic Versioning](https://semver.org/).

## Make a release

Development and releases are made from the `main` branch directly, therefore the branch should remain in releasable state at any time.

Creating a release involves creating a Git tag and pushing it to the upstream repository.

Tags should follow the simple `MAJOR.MINOR.PATCH` format, without any prefix (e.g. do not include the `v` prefix).

Step 1) Make a release tag.

```bash
tag="MAJOR.MINOR.PATCH"
git tag -s "${tag}" -m "${tag}"
git push origin "${tag}"
```

Step 2) Make the GitHub Release and Release Notes.

> Release notes generation is automated and based on the enforced labelling of pull requests.
> As pull requests are merged, they are required to be tagged with `semver/*` tags (`semver/patch`, `semver/minor`, ...).

Navigate to the [New release](https://github.com/swift-server/swift-prometheus/releases/new) page on github and 
select your release tag.

Click **Generate release notes** release notes will automatically be generated.

Take a moment to read over the changes and make sure their assigned patch/minor/major categories are correct and match the release's assigned version.

You may add some additional introduction, thanks or additional information which may be useful for anyone reading the release notes.

Step 3) "There is no Step 3!"

## Swift Versions

Generally this project supports three most recent minor versions of Swift.

For example, at time of writing this document Swift 6.2 is the current release, so this project also supports 6.1 and 6.0.
And this list of versions changes whenever a new minor Swift version is released.
