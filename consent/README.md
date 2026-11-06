# cookiejar consent

[`assets/cookiejar-consent.js`](assets/cookiejar-consent.js) is a cookie consent
banner for your site that lists the cookies of a [cookiejar scan](../scanner/README.md)
report by category. Visitors can
accept or reject all optional cookies, or pick categories in the cookie settings,
which list every cookie with its provider, purpose and duration. It supports
[Google Consent Mode v2](https://developers.google.com/tag-platform/security/guides/consent),
needs no other libraries, and comes with English and German texts.

## Building the banner

`cookiejar-consent` builds the banner script with the cookies of a report built in:

```sh
cookiejar-consent -w public/cookie-consent.js                  # from the newest report in cookie-report
cookiejar-consent cookie-report/cookies-20261005-143012.csv -w public/cookie-consent.js --options banner.yml
cookiejar-consent -w public/cookies.json                       # only the cookie list, as JSON
```

| Option | Default | Description |
| --- | --- | --- |
| `-r, --reports DIR` | `cookie-report` | Directory with reports, used when no report file is given |
| `-w, --write FILE` | stdout | File to write |
| `--format FORMAT` | from `--write`, else `js` | `js` for the banner script, `json` for the cookie list only |
| `--options FILE` | | YAML or JSON file with [banner options](#banner-options) to build in |
| `--unknown CATEGORY` | `unknown` | Where to list `unknown` cookies: in their own "Other" category, or in `performance` or `marketing` |

Check the report before publishing the banner: cookies listed as `unknown` and
descriptions you'd like to word differently are best fixed with a [custom rules file](../scanner/README.md#classification)
and a new scan, so the next scan keeps them.

### Installation

With Ruby >= 3.2, from a checkout of this repository:

```sh
cd consent
bundle install
bundle exec exe/cookiejar-consent --help
```

or with Docker, published for amd64 and arm64 as `sarhanalaa/cookiejar-consent`.
The container works in `/work`, so mount the directory that holds `cookie-report/`:

```sh
docker run --rm -v "$PWD:/work" sarhanalaa/cookiejar-consent -w public/cookie-consent.js
```

On Linux, add `--user "$(id -u):$(id -g)"` so the written files are owned by you.
### From npm or a CDN

The plain script, without cookies built in, is published to npm as
[`cookiejar-consent`](https://www.npmjs.com/package/cookiejar-consent):

```sh
npm install cookiejar-consent    # node_modules/cookiejar-consent/assets/cookiejar-consent.js
```

or load it from a CDN, pinned to a version:

```html
<script src="https://cdn.jsdelivr.net/npm/cookiejar-consent@0.1.0/assets/cookiejar-consent.js"
        data-cookies-url="/cookies.json" data-privacy-policy-url="/privacy"></script>
```

Give the plain script its cookies with `cookiesUrl` (or `data-cookies-url`),
pointing at a cookie list built with `cookiejar-consent --format json`, or in
`window.cookiejarConsentConfig.cookies` (see [Banner options](#banner-options)).
This way the cookies can be updated without replacing the script. Self-host the
script for production if you can: a third-party CDN in front of your consent
banner is one more party that sees your visitors' requests.

## Adding it to a site

Load the script synchronously in `<head>`, before Google Tag Manager or `gtag.js`:

```html
<script src="/cookie-consent.js" data-privacy-policy-url="/privacy" data-imprint-url="/imprint"></script>
<!-- Google Tag Manager snippet follows here -->
```

and add a link to the cookie settings to every page, usually in the footer:

```html
<a href="#" data-cookiejar-preferences>Cookie settings</a>
```

The banner shows until the visitor decides. Their choice is stored for 180 days
in the first-party cookie `cookiejar_consent`.

The categories of the report become consent categories: `functionality`
("Necessary") is always active, `performance` ("Analytics"), `marketing` and
`unknown` ("Other", only shown when the report has such cookies) need consent.

## Google Consent Mode

Before any tag runs, the script sets the Consent Mode defaults, with everything
but necessary storage denied, and applies a stored choice right after. Whenever
the visitor decides, it sends a consent update:

| Category | Consent Mode types |
| --- | --- |
| `functionality` | `functionality_storage`, `personalization_storage`, `security_storage` (always granted) |
| `performance` | `analytics_storage` |
| `marketing` | `ad_storage`, `ad_user_data`, `ad_personalization` |

Google tags adjust to the consent on their own. For other tags in Google Tag
Manager, use the `cookie_consent_update` event the banner pushes to the data
layer, with the choice in `cookie_consent` (e.g. `cookie_consent.marketing`), or
GTM's built-in consent checks.

## Blocking scripts without consent

Scripts and embeds outside a tag manager can wait for consent too. Give them a
category and `type="text/plain"` or `data-src`; they run or load once the category
is accepted:

```html
<script type="text/plain" data-cookie-category="performance" src="https://analytics.example/script.js"></script>
<iframe data-cookie-category="marketing" data-src="https://www.youtube-nocookie.com/embed/..."></iframe>
```

When a visitor withdraws consent, the banner deletes the category's first-party
cookies listed in the report. Third-party cookies can't be deleted by the site.

## Banner options

Options can be built in with `--options`, set in `window.cookiejarConsentConfig`
before the script loads, or for the common ones, set as `data-` attributes of the
script tag. Later ones override earlier ones.

```yaml
revision: 2                     # bump to ask all visitors again, e.g. after adding a new tool
language: de                    # default: the page's lang attribute, then the browser language
privacyPolicyUrl: /datenschutz  # data-privacy-policy-url
imprintUrl: /impressum          # data-imprint-url
storage:
  cookieName: cookiejar_consent
  cookieDomain: example.com     # data-cookie-domain; share the choice across subdomains
  maxAgeDays: 180
googleConsentMode:
  enabled: true
  waitForUpdate: 500            # ms tags wait for a consent update on first load
  adsDataRedaction: true
  urlPassthrough: false
  region: []                    # e.g. [DE, AT]: apply the defaults only in these regions
dataLayerEvent: cookie_consent_update
deleteCookiesOnWithdraw: true
reloadOnWithdraw: false         # reload so tags that already ran stop
recordUrl: https://consent.example.com/consents  # data-record-url; see "Recording consents"
theme:                          # CSS custom properties of the banner, without --cj-
  accent: "#0b7a53"
  radius: 4px
texts:                          # override texts, for all languages or per language
  de:
    bannerTitle: Cookies auf example.com
    categories:
      performance: { title: Statistik, description: "..." }
```

With `cookiesUrl` (or `data-cookies-url`), the plain script from `assets/` loads
the cookie list from a JSON file written by `cookiejar-consent --format json`
instead of having it built in.

## Recording consents

To prove what visitors consented to, the banner can send a record of every
decision to a consent log: set `recordUrl`. The [receiver](../receiver/README.md)
is a small self-hosted log that appends records to daily JSON Lines files, ready to run in Docker.
Records hold the visitor's random consent ID (also in their consent cookie), the
choice per category, the time, the page, and which banner they saw: its
`revision`, report and a fingerprint of its cookies and options. Keep every
banner you publish, so a record's fingerprint leads back to what the visitor saw.

## JavaScript API

```js
CookiejarConsent.hasConsent("marketing")   // true or false
CookiejarConsent.getConsent()              // { functionality: true, performance: false, ... } or null
CookiejarConsent.onChange((consent, source) => { ... })  // also called right away if consent is known
CookiejarConsent.showPreferences()         // open the cookie settings
CookiejarConsent.acceptAll() / rejectAll() / setConsent({ performance: true })
CookiejarConsent.reset()                   // forget the choice and ask again
```

The page also receives a `cookiejar:consent` event on `document` on every change.

## Development

```sh
cd consent
bundle exec rspec
```

The banner's specs run it in a real headless browser: `BROWSER_PATH`, the Chromium
installed by the scanner's `script/install-chromium`, or any Chrome Ferrum finds.
Set `SKIP_BROWSER_SPECS=1` to skip them.
