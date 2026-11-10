# Contributing to the project 

The information in this page is primarily for those who wish to contribute to the c2pa-swift project itself, rather than those who simply wish to use it in an application.  For general contribution guidelines, see [CONTRIBUTING](../CONTRIBUTING.md).

## Building from Source

1. Clone this repository:

   ```bash
   git clone https://github.com/contentauth/c2pa-swift.git
   cd c2pa-swift
   ```

2. Build the iOS framework:

   ```bash
   # Build library framework
   make library

   # Or build entire workspace
   make workspace-build
   ```

3. Run tests:

   ```bash
   # Run all tests
   make test

   # Run with coverage
   make coverage
   ```

## Test App

The app includes comprehensive tests covering all major C2PA operations. Run the app and tap "Run All Tests" to see the library in action.

- **C2PA Library Version** - Display current library version
- **Error Handling** - Proper error handling for invalid files
- **Reading C2PA Data** - Extract manifest data from signed images
- **Stream APIs** - Demonstrate flexible stream-based operations
- **Builder APIs** - Sign images with custom manifest data
- **No-Embed Manifests** - Create cloud/sidecar manifests
- **Resource Management** - Add and extract resources (thumbnails, etc.)
- **Ingredient Support** - Handle ingredient relationships
- **Archive Operations** - Work with C2PA archives
- **Custom Signers** - Implement callback-based signing
- **Hardware Signing** - Use Secure Enclave for signing (iOS devices)

## API documentation 

The first tag in [docs/versions.json](docs/versions.json) is the default
at the existing `/c2pa-swift/documentation/c2pa/` URL. Each release is also
available at `/c2pa-swift/versions/<tag>/documentation/c2pa/`.

To build the versioned site locally, install Xcode 16.4 with its iOS SDK,
Bash 3.2 or newer, `jq`, Git, and the [GitHub CLI](https://cli.github.com/). Authenticate
using `gh auth login` or `GH_TOKEN`, and fetch the selected release tags:

```sh
git fetch --tags
make docs-versioned
```

If your active developer directory points to Command Line Tools rather than
Xcode, select Xcode for this command without changing the system configuration:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make docs-versioned
```

The builder verifies each published release, exports its exact tag into an
isolated temporary directory, and runs that release's own `make docs` for a
generic iOS Simulator destination, so each release builds with the recipe it
shipped with. All releases build with the one Xcode the workflow selects, which
must therefore still build the oldest listed release. It does not change your checkout or require
a running simulator. The temporary source and build directories are removed
after the build, including on failure. GitHub authentication tokens are not
passed to the Xcode builds.

The output is `docs-output/`, with the default at `index.html` and releases
under `versions/<tag>/`. DocC's routing uses the `/c2pa-swift` hosting base path,
so preview it over HTTP at that path rather than opening HTML with `file://`.
The selector stays available when navigating between DocC pages.

The release workflow puts each stable release first in
[docs/versions.json](versions.json), in the same commit that updates
`Package.swift`, and then rebuilds and deploys the site with that release as
the default. Pre-releases are not added and do not rebuild the site. To document another release or change
the default, edit the list and keep the default first. Documentation changes
on `main` and manual workflow runs also rebuild and deploy the site. Pull
requests build and validate the docs without deploying them.

The existing `make docs` command still builds working-tree documentation.
`make docs-versioned` fails if a release has no landing page, a page has no
head element to carry the selector, or the assembled site's root does not
lead to the default version, so the real build is the test.
