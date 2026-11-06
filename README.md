# cookiejar

Open-source tooling for cookie compliance, from finding out which cookies a site
sets to proving what visitors consented to. It consists of three independent
components that work together through plain files and HTTP:

```
             report (CSV)               banner (JS)               consent records
 scanner  ───────────────▶  consent  ───────────────▶  your site  ───────────────▶  receiver
 crawls your site            builds the banner           visitors                   append-only
 in headless Chromium        with your cookies           decide                     consent log
```

| Component | What it does | Published as |
| --- | --- | --- |
| [**scanner**](scanner/README.md) | Crawls a site in a real headless browser, accepts consent banners, and writes a CSV report of every cookie, classified as `functionality`, `performance`, `marketing` or `unknown`. Compares reports of consecutive scans. | `sarhanalaa/cookiejar-scanner` |
| [**consent**](consent/README.md) | A dependency-free cookie consent banner with Google Consent Mode v2 support, and `cookiejar-consent`, which builds it with the cookies of a report. | `sarhanalaa/cookiejar-consent`, npm [`cookiejar-consent`](https://www.npmjs.com/package/cookiejar-consent) |
| [**receiver**](receiver/README.md) | A small self-hosted consent log that stores each visitor's decision in daily JSON Lines files, as evidence under GDPR Art. 7(1). | `sarhanalaa/cookiejar-receiver` |

Each component can be used on its own: the scanner's report is a plain CSV, the
banner works with a hand-written cookie list, and the receiver accepts records
from any client that sends its format.

## Quick start

```sh
# 1. Scan your site; writes cookie-report/cookies-<time>.csv
docker run --rm --init -v "$PWD:/reports" sarhanalaa/cookiejar-scanner https://www.example.com/

# 2. Build the banner from the newest report
docker run --rm -v "$PWD:/work" sarhanalaa/cookiejar-consent -w cookie-consent.js

# 3. Optionally, run the consent log the banner reports to (set recordUrl in the banner options)
docker run -d -p 9292:9292 -v consent-log-data:/data \
  -e ALLOWED_ORIGINS=https://www.example.com -e ADMIN_TOKEN=... sarhanalaa/cookiejar-receiver
```

Then load `cookie-consent.js` in the `<head>` of your pages, before your tag
manager. See each component's README for all options.

## Repository layout

```
scanner/    Ruby gem and CLI `cookiejar` (scan, diff)
consent/    Banner script (assets/cookiejar-consent.js, npm package) and Ruby gem and CLI `cookiejar-consent`
receiver/   Rack app and CLI `bin/consent-log`
.github/    CI and image publishing
```

Each directory has its own `Gemfile`, specs, `Dockerfile` and version, and is
released on its own.

## Releases

Docker images are published on [Docker Hub](https://hub.docker.com/u/sarhanalaa) for
`linux/amd64` and `linux/arm64` by [`.github/workflows/docker.yml`](.github/workflows/docker.yml),
and mirrored to the GitHub Container Registry as `ghcr.io/alaasarhan/cookiejar-<component>`:

* every push to `main` publishes the `edge` tag of each image;
* a tag `<component>-v<version>`, e.g. `scanner-v1.2.0`, publishes that component's
  image as `1.2.0`, `1.2`, `1` and `latest`. Pre-releases such as `1.2.0-rc.1` get
  only their own tag.

Images carry build provenance attestations and an SBOM. Verify an image with
`gh attestation verify oci://index.docker.io/sarhanalaa/cookiejar-scanner:latest --owner AlaaSarhan`.

The banner script is also published to npm as [`cookiejar-consent`](https://www.npmjs.com/package/cookiejar-consent)
by [`.github/workflows/npm.yml`](.github/workflows/npm.yml) on each `consent-v*`
tag, with npm provenance.

To release a component, bump its version (`scanner/lib/cookiejar/version.rb`,
`consent/lib/cookiejar_consent/version.rb` and `consent/package.json`, or
`receiver/lib/consent_log.rb`), add the changes to [CHANGELOG.md](CHANGELOG.md),
and push the tag. The release fails if the tag doesn't match the version.

## Contributing

Contributions are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Please report
security issues as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). The scanner can use the [Open Cookie Database](https://github.com/jkwakman/Open-Cookie-Database),
which is licensed separately under the Apache License 2.0 and not part of this
repository, except for a small excerpt used as a test fixture.
