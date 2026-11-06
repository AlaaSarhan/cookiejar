# Contributing

Thanks for helping with cookiejar! Bug reports, cookie classification rules,
consent platform selectors, translations of the banner and code are all welcome.

## Getting started

The repository holds three independent components, each with its own `Gemfile`
and specs. Work in the directory of the component you change:

```sh
cd scanner    # or consent, receiver
bundle install
bundle exec rspec
```

The scanner's and the banner's specs launch a headless Chromium. Install one with
`scanner/script/install-chromium`, or set `SKIP_BROWSER_SPECS=1` to skip those specs.
Ruby 3.2 is the oldest supported version.

## Pull requests

* Keep a pull request to one component where you can. A change to the report
  format affects both the scanner and the consent builder; change and test both.
* Add specs for new behaviour and keep the suites green; CI runs them for each component.
* Update the component's README when behaviour or options change, and add a line
  to [CHANGELOG.md](CHANGELOG.md) under "Unreleased".
* Cookie rules (`scanner/data/cookie_rules.yml`) need a source for the cookie's
  purpose, such as the vendor's documentation, in the pull request description.

## Releases

Maintainers release a component by bumping its version (for the consent
component, in both `lib/cookiejar_consent/version.rb` and `package.json`), moving
its changelog entries under the new version and pushing a tag
`<component>-v<version>`. That publishes its Docker image, and for the consent
component, the npm package.
