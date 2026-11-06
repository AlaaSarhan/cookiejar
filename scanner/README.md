# cookiejar scanner

Scans websites for cookies and writes a CSV report of all cookies and their
category, ready to feed into a cookie consent configuration such as the
[cookiejar consent banner](../consent/README.md). Reports of consecutive scans
can be compared to see which cookies were added, changed or removed.

Pages are loaded in a real headless Chromium-based browser, so the scan captures
cookies set by JavaScript and by third-party resources as well as those sent in
`Set-Cookie` headers. Cookie consent banners are accepted automatically, so cookies
that are only set after consent are captured too.

## Requirements

* Ruby >= 3.2
* A Chromium-based browser. `script/install-chromium` installs one for the scanner (see below).
  Otherwise an installed Chrome, Chromium, Edge or Brave is used. Brave blocks many
  tracking cookies, so it gives incomplete results.

## Installation

From a checkout of this repository:

```sh
cd scanner
bundle install
script/install-chromium   # install a headless Chromium into vendor/chromium
bundle exec exe/cookiejar --help
```

Or run it in [Docker](#docker), which needs neither Ruby nor a browser installed.
Either way, download the [Open Cookie Database](#open-cookie-database) for more
accurate classification.

### Headless Chromium

`script/install-chromium` downloads Google's [Chrome for Testing](https://googlechromelabs.github.io/chrome-for-testing/)
build of `chrome-headless-shell` for your OS (macOS arm64/x64, Linux x64, Windows
64/32-bit) into `vendor/chromium`. The scanner then uses it automatically. Running
it again updates to the latest version or does nothing if you're already on it.

The browser is chosen in this order: `--browser-path`, the `BROWSER_PATH` env var,
the Chromium from `script/install-chromium`, an installed Chrome, then Chromium, Edge or Brave.

| Variable | Default | Description |
| --- | --- | --- |
| `CHROME_FLAVOR` | `chrome-headless-shell` | `chrome` installs the full browser, which can also run with `--no-headless` |
| `CHROME_CHANNEL` | `Stable` | `Beta`, `Dev` or `Canary` |
| `CHROME_VERSION` | latest | An exact version, e.g. `CHROME_VERSION=131.0.6778.85 script/install-chromium` |

Delete `vendor/chromium` to remove it again.

* **Windows:** run `ruby script/install-chromium`.
* **Linux:** the browser needs some system libraries. If it doesn't start, the
  installer lists the missing ones. Installing your distribution's `chromium`
  package pulls them in.
* **Linux ARM:** Chrome for Testing has no build for this platform. Install your
  distribution's Chromium instead (`sudo apt install chromium`); it's found automatically.

### Docker

The image includes Ruby, the gems and Debian's Chromium, so you don't need
anything else installed. It is published for amd64 and arm64 as
`sarhanalaa/cookiejar-scanner`.

```sh
docker run --rm --init \
  -v "$PWD:/reports" \
  -v "$PWD/cookie-database:/cookie-database:ro" \
  sarhanalaa/cookiejar-scanner https://example.com/
```

To build it yourself: `docker build -t cookiejar-scanner scanner`.

Options and start URIs are passed straight through to `cookiejar`. The container
works in `/reports`, so with the current directory mounted there, reports go to
`./cookie-report` as usual, and config and rules files are found by relative
path (`-c scan.yml`). Diff reports with `docker run --rm -v "$PWD:/reports" sarhanalaa/cookiejar-scanner diff`.
Report names use the container's time zone, UTC by default. Pass `-e TZ=Europe/Berlin`
for local time. On Linux, add `--user "$(id -u):$(id -g)"` so the reports are owned by you.

The [Open Cookie Database](#open-cookie-database) is not part of the image. The
container reads it from `/cookie-database/open-cookie-database.csv`, so mount a
directory containing `open-cookie-database.csv` at `/cookie-database`. Without
it, the scan logs a warning and classifies cookies with the built-in rules only.

## Usage

```sh
cookiejar [options] START_URI [START_URI...]
```

Examples:

```sh
# Scan the home page and the pages it links to (depth 1, the default)
cookiejar https://example.com/

# Only the start pages, without following links
cookiejar --no-follow-links https://example.com/ https://example.com/shop

# Crawl deeper, skipping the admin area and PDF links
cookiejar --depth 3 --exclude-path '/admin/**' --exclude-href '**.pdf' https://example.com/
```

### Options

| Option | Default | Description |
| --- | --- | --- |
| `-c, --config FILE` | | YAML config file (CLI options take precedence) |
| `--[no-]follow-links` | on | Follow links found on pages |
| `-d, --depth N` | 1 | Max link depth from a start URI |
| `--max-pages N` | 100 | Stop after visiting N pages |
| `--allow-domain DOMAIN` | start URI hosts | Follow links to DOMAIN and its subdomains |
| `--include-href PATTERN` | | Only follow links whose `href` attribute matches |
| `--exclude-href PATTERN` | | Never follow links whose `href` attribute matches |
| `--include-path PATTERN` | | Only follow links whose URL path matches |
| `--exclude-path PATTERN` | | Never follow links whose URL path matches |
| `-o, --output DIR` | `cookie-report` | Directory for the CSV report |
| `--threshold N` | 0.8 | Minimum confidence (exclusive) to assign a category |
| `--rules FILE` | | YAML file with custom rules that override built-in ones |
| `--cookie-database FILE` | `COOKIE_DATABASE` | [Open Cookie Database](#open-cookie-database) CSV |
| `--include-values` | off | Include cookie values in the full details JSON |
| `--browser-path PATH` | auto | Chromium-based browser binary |
| `--timeout SECONDS` | 30 | Page load timeout |
| `--settle SECONDS` | 2 | Consider a page loaded once no request started or finished and no cookie changed for this long |
| `--max-settle SECONDS` | 15 | Max wait for a page to settle, for pages that never go quiet |
| `--[no-]headless` | on | Run the browser headless |
| `--[no-]accept-consent` | on | Accept cookie consent banners to load all cookies |
| `--consent-selector SELECTOR` | | CSS selector of a site's accept button, tried first (repeatable) |
| `--consent-wait SECONDS` | 5 | How long to wait for a banner on the first page of each host |

Link filter options can be repeated or given comma separated. Patterns support
`*` (any characters within a path segment), `**` (any characters across segments)
and `?` (a single character).

Each page is loaded at most once per scan. URLs that differ only in their
fragment (`#...`), the case of the scheme or host, or an explicit default port
count as the same page, and so does the URL a page redirected to. Duplicates are
skipped and do not count towards `--max-pages`.

After each page load the scanner waits for the page to settle: until no network
request started or finished and no cookie changed for `--settle` seconds, but at
most `--max-settle` seconds. Tag managers such as Google Tag Manager load tags in
waves, often from timers, so the network goes quiet between waves. If cookies
from tags with long delays are missing, raise `--settle`.

### Config file

Every option can also be set in a YAML file passed with `--config`. List values
from the command line are appended to those from the file.

```yaml
start_uris:
  - https://example.com/
follow_links: true
depth: 2
max_pages: 200
allowed_domains: [example.com, shop.example.com]
exclude_paths: ["/admin/**"]
exclude_hrefs: ["**.pdf"]
output_dir: reports/example
confidence_threshold: 0.8
settle_time: 3
max_settle_time: 20
```

### Cookie consent

Most sites only set analytics and marketing cookies after the visitor accepts
them, so the scanner accepts the consent banner on each page before collecting
cookies. Cookies seen before and after consent are both included. Banners are
found in the page, in shadow DOM, and in iframes, using these methods in order:

1. Selectors passed with `--consent-selector`
2. The accept buttons of known consent platforms: OneTrust, Cookiebot, Usercentrics,
   Didomi, Sourcepoint, Quantcast, TrustArc, consentmanager, CookieYes, Complianz,
   Borlabs, Klaro, and [others](lib/cookiejar/auto_consent.rb)
3. A visible "accept all" style button in a cookie banner, recognised by its text
   in English, German, French, Spanish, Italian, Portuguese, Dutch, Scandinavian,
   Finnish, Polish, Czech, and Russian. Buttons that reject, accept only necessary
   cookies, or open settings are never clicked.

After accepting, the scanner waits for the page to settle again (consent
platforms often store the consent asynchronously, and tag managers fire
consent-gated tags right away), then reloads the page so tags that wait for
consent on page load also run. Each accepted banner is logged. If a site's banner isn't recognised,
pass its accept button with `--consent-selector`. Use `--no-accept-consent` to
scan what a visitor gets before consenting.

## Output

Each scan writes one CSV file with all cookies to the output directory, named
after the time of the scan, e.g. `cookie-report/cookies-20261005-143012.csv`, so
consecutive scans don't overwrite each other. Cookies are sorted by category,
then name. The file has these columns:

| Column | Content |
| --- | --- |
| cookie name | The cookie's name |
| category | `functionality`, `performance`, `marketing` or `unknown`, see below |
| cookie purpose/description | What the cookie is used for, from the matching rule |
| storage duration | Remaining lifetime, e.g. `3 months`, or `Session` |
| security settings | Flags such as `Secure; HttpOnly; SameSite=Lax` |
| full details | JSON with all cookie attributes, the classification, the Open Cookie Database entry and the page where it was first seen |

The categories are:

* `functionality`: cookies required for the site's core features (sessions,
  security, load balancing, consent storage)
* `performance`: analytics, error reporting, and A/B testing cookies
* `marketing`: cookies from third-party marketing and advertising platforms
* `unknown`: cookies where no category scored above the confidence threshold

For `unknown` cookies that matched a rule below the threshold, the full details
include the suggested category.

The report is the input of the [consent banner](../consent/README.md). Its columns
are a stable interface: new columns may be added, but existing ones are not renamed
or removed without a major version bump.

### Comparing scans

```sh
cookiejar diff                              # the two newest reports in cookie-report
cookiejar diff -o reports/example           # the two newest reports in another directory
cookiejar diff cookie-report/cookies-20261001-090000.csv cookie-report/cookies-20261005-143012.csv
```

`cookiejar diff` lists the cookies that were added,
modified or removed between two reports. Modified cookies are listed with the
fields that changed. Cookies are told apart by name, domain and path. Values
that change on every visit are ignored: the cookie value and size, the absolute
expiry time, and the pages the cookie was seen on.

Sites that run ad auctions load different ad partners on each visit, so their
reports differ between scans even when nothing on the site changed.

## Classification

Cookies are classified using the rules in [`data/cookie_rules.yml`](data/cookie_rules.yml),
from most to least specific:

1. Custom cookie name rules from `--rules`, which override everything else
2. Built-in cookie name rules
3. Whichever is more confident of:
   * The cookie's entry in the [Open Cookie Database](#open-cookie-database)
   * Fallback evidence from the cookie's domain and keywords in its name. Signals
     for the same category are combined, so two weak signals can together pass
     the threshold.

A custom rules file uses the same format as the built-in one:

```yaml
cookies:
  - { name: "acme_*", category: functionality, provider: Acme, confidence: 0.95, description: "Acme storefront state." }
domains:
  - { domain: tracker.example, category: marketing, provider: Example Tracker, confidence: 0.9 }
keywords:
  - { pattern: "^exp_", category: performance, confidence: 0.85, description: "A/B test assignment." }
```

### Open Cookie Database

The scanner looks cookies up in the [Open Cookie Database](https://github.com/jkwakman/Open-Cookie-Database),
a community-maintained list of over 2,000 cookies with their platform, purpose
and retention period. It isn't included in this repository or the Docker image. Download it
(again, to update it) and pass it with `--cookie-database FILE` or the `COOKIE_DATABASE`
env var, or mount its directory in [Docker](#docker):

```sh
mkdir -p cookie-database
curl -fsSL -o cookie-database/open-cookie-database.csv \
  https://raw.githubusercontent.com/jkwakman/Open-Cookie-Database/master/open-cookie-database.csv
```

Without it, the scan logs a warning and classifies cookies with the built-in rules
only, so more cookies end up `unknown`.

When a cookie has an entry, it is added to the cookie's full details as
`openCookieDatabase`, even when another rule decided the category. Its categories
map as follows: Functional, Necessary, Security and Personalization to
`functionality`, Analytics to `performance`, Marketing to `marketing`.

| Match | Confidence |
| --- | --- |
| Name, and the cookie is set on the entry's domain | 0.95 |
| Exact name | 0.9 |
| Name prefix (wildcard entries) | 0.85 |
| Generic name not set on the entry's domain | 0.6 |

The database's domain is the platform's domain, but many platforms set their
cookies on the visited site, so a cookie set on another domain still matches.
Names that are too generic to identify a platform on their own only count when
the cookie is set on the entry's domain; otherwise they end up `unknown` with a
suggested category. Generic names are those of up to three characters (e.g. `IDE`,
`c`) and plain lowercase words listed for a platform's domain (e.g. `sessionid`
for Instagram, `locale` for Facebook).

The Open Cookie Database is licensed under the [Apache License 2.0](https://github.com/jkwakman/Open-Cookie-Database/blob/master/LICENSE).

## Development

```sh
cd scanner
bundle exec rspec
```

The integration specs launch a real browser. Set `SKIP_BROWSER_SPECS=1` to skip
them on machines without a Chromium-based browser.
