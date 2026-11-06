# Changelog

Each component is versioned and released on its own.

## Unreleased

### All components
* Restructured the repository into `scanner/`, `consent/` and `receiver/`, each
  with its own gem or app, specs, README and Docker image.
* Docker images are published to Docker Hub as `sarhanalaa/cookiejar-<component>`
  for amd64 and arm64, mirrored to the GitHub Container Registry.

### scanner 0.1.0
* `cookiejar banner` moved to the consent component as `cookiejar-consent`.

### consent 0.1.0
* New `cookiejar-consent` command and gem to build the banner from a scanner report.
  Its `--reports DIR` option replaces `cookiejar banner --output DIR`.
* The banner script is published to npm as `cookiejar-consent`.

### receiver 0.1.0
* First release.
