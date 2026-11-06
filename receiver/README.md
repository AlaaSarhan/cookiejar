# cookiejar receiver

A consent log: stores the decisions visitors make in the [cookiejar consent banner](../consent/README.md),
so you can prove who consented to what, and when (GDPR Art. 7(1)). It is a small
Rack app that appends records to plain text files, independent of the scanner.

Records are stored as [JSON Lines](https://jsonlines.org), one record per line,
in one file per day (UTC) of receipt:

```
data/consents-2026-11-06.jsonl
data/consents-2026-11-07.jsonl
```

```json
{"consent_id":"0b6d8f1e-1c2d-4e5f-9a8b-7c6d5e4f3a2b","received_at":"2026-11-06T10:00:00.120Z","client_time":"2026-11-06T10:00:00.084Z","action":"custom","functionality":true,"performance":true,"marketing":false,"unknown":false,"revision":"2","report":"cookies-20261105-120000.csv","fingerprint":"a1b2c3d4e5f6a7b8","url":"https://www.example.com/pricing","language":"de","banner_version":"1"}
```

Each record holds:

| Field | Content |
| --- | --- |
| `consent_id` | Random ID of the visitor's choice, also stored in their `cookiejar_consent` cookie |
| `received_at` | When the log received the record (server time) |
| `client_time` | When the visitor decided (browser time) |
| `action` | `accept_all`, `reject_all`, `custom` (saved in the settings) or `api` (set by the site's code) |
| `functionality`, `performance`, `marketing`, `unknown` | The choice per category |
| `revision`, `report`, `fingerprint` | Which banner the visitor saw, see [Proving what visitors saw](#proving-what-visitors-saw) |
| `url` | Page of the decision, without query and fragment |
| `language`, `banner_version` | Banner language and script version |

No IP addresses, user agents or other cookies are stored. The log only ever
appends to the current day's file and answers only once the record is on disk.
Once a day is over, its file never changes again.

## Running it

```sh
cd receiver
bundle install
ALLOWED_ORIGINS=https://www.example.com ADMIN_TOKEN=$(openssl rand -hex 32) bundle exec puma -C puma.rb
```

or with Docker:

```sh
docker run -d --name consent-log -p 9292:9292 -v consent-log-data:/data \
  -e ALLOWED_ORIGINS=https://www.example.com -e ADMIN_TOKEN=... \
  sarhanalaa/cookiejar-receiver
```

The image is published for amd64 and arm64. To build it yourself:
`docker build -t cookiejar-receiver receiver`. In the container, the command line
tool runs as `docker exec consent-log bundle exec bin/consent-log ...`.

Then point the banner at it:

```sh
cookiejar-consent -w public/cookie-consent.js --options banner.yml   # with recordUrl: https://consent.example.com/consents
```

or set it on the script tag: `data-record-url="https://consent.example.com/consents"`.

| Variable | Default | Description |
| --- | --- | --- |
| `ALLOWED_ORIGINS` | required | Comma-separated origins of the sites that may send records, e.g. `https://example.com,https://www.example.com`; `*` for any |
| `ADMIN_TOKEN` | | Bearer token for reading records; without it, records can only be read with `bin/consent-log` |
| `DATA_DIR` | `data` (`/data` in Docker) | Directory of the record files; must exist |
| `RATE_LIMIT` | 60 | Records per client IP and minute; 0 to disable |
| `PORT` | 9292 | |
| `PUMA_THREADS` | 5 | |

Run it behind your HTTPS reverse proxy or load balancer. It runs as a single
process that serialises writes. Don't run several instances on the same
directory: their writes could interleave.

The banner sends records with `navigator.sendBeacon` as `text/plain`, so they
need no CORS preflight and still arrive when the visitor leaves the page right
after deciding. The log checks the `Origin` header, or the `Referer` where
browsers leave out `Origin` (beacons to another subdomain of the same site). Pages
with `Referrer-Policy: no-referrer` therefore can't record to another subdomain:
serve the log under the site's own origin (e.g. proxy `/consent-log/` to it) or
loosen the policy to `strict-origin-when-cross-origin`, the browser default.

Ad blockers may block requests to hosts or paths that look like tracking. A path on
the site's own domain is the most reliable choice.

## Backups

The files are the evidence. Keep them on a persistent volume and copy them off
the server regularly, e.g. every few minutes from cron:

```sh
aws s3 sync /data s3://my-bucket/consent-log --exclude "*" --include "consents-*.jsonl"
```

Files are safe to copy while the log is running. Only the current day's file
still grows, and a copy taken mid-write at worst ends in a partial line that the
next copy completes.

For the strongest proof against tampering, store the copies in write-once
storage, e.g. an S3 bucket with [Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
in compliance mode with the retention period below. A finished day's file can
then be neither changed nor deleted before it expires, not even by an administrator.

If the log crashes in the middle of a write, the file can end in a partial line.
The log starts the next record on a new line and skips the damaged one when
reading, with a warning in its log.

## Reading records

```sh
# All records of one visitor's consent ID, oldest first
curl -H "Authorization: Bearer $ADMIN_TOKEN" https://consent.example.com/consents/0b6d8f1e-1c2d-4e5f-9a8b-7c6d5e4f3a2b

# Export as JSON lines or CSV, optionally by time received
curl -H "Authorization: Bearer $ADMIN_TOKEN" "https://consent.example.com/consents?format=csv&from=2026-11-01T00:00:00Z&to=2026-12-01T00:00:00Z"

# The same on the server, without the HTTP API
bin/consent-log export --from 2026-11-01T00:00:00Z --csv
```

Without the API, the files can also be searched directly, e.g.
`grep -h 0b6d8f1e-1c2d-4e5f-9a8b-7c6d5e4f3a2b data/consents-*.jsonl`.

`GET /health` returns `ok` while the data directory is writable.

## Retention

Keep records for as long as the consent is valid, plus the period in which
claims can be brought. With the banner's 180-day consent cookie and Germany's
standard limitation period of three years from the end of the year, that is
about four years. Check the period with your data protection officer, then purge
older records regularly, e.g. daily from cron:

```sh
bin/consent-log purge --older-than 1460
```

This deletes the files of days that ended more than 1460 days ago; records are
purged a whole day at a time. Copies in other storage, such as backups, need
their own expiry rule, e.g. an S3 lifecycle rule.

## Proving what visitors saw

A record that says "accepted revision 3" proves nothing unless you can show what
revision 3 listed. Every banner built with `cookiejar-consent` carries the name of
its report and a fingerprint of its cookies and options, and both end up in each
record. Keep each banner you publish, e.g. by committing the generated script and
its report to version control, so the fingerprint in a record leads to the
banner the visitor saw.

Texts or options set on the page at runtime (`window.cookiejarConsentConfig`,
`data-` attributes) are not part of the fingerprint. Build them in with
`--options` if you need them covered.

## Development

```sh
cd receiver
bundle exec rspec
```
