/*!
 * cookiejar consent banner
 *
 * A cookie consent banner that lists the cookies of a cookiejar scan report by
 * category, lets visitors accept or reject each category, and drives Google
 * Consent Mode v2. See consent/README.md in the cookiejar repository.
 *
 * Load it synchronously in <head>, before Google Tag Manager or gtag.js, so the
 * consent defaults are set before any tag runs.
 */
(function (window, document) {
  "use strict";

  // Replaced with the site's cookies and options by `cookiejar-consent`.
  var EMBEDDED_CONFIG = /*COOKIEJAR_CONFIG*/ null;

  var CATEGORIES = ["functionality", "performance", "marketing", "unknown"];
  var REQUIRED = "functionality";

  var TEXTS = {
    en: {
      bannerTitle: "We use cookies",
      bannerText:
        "We use cookies and similar technologies to run this website, to understand how it is used and for marketing. " +
        "You can accept all of them, reject the optional ones or choose which categories to allow. " +
        "You can change your choice at any time in the cookie settings.",
      acceptAll: "Accept all",
      rejectAll: "Reject all",
      customize: "Customize",
      save: "Save selection",
      close: "Close",
      preferencesTitle: "Cookie settings",
      preferencesText:
        "Choose which cookies we may use. Necessary cookies are always active because the website does not work without them.",
      privacyPolicy: "Privacy policy",
      imprint: "Imprint",
      alwaysActive: "Always active",
      showCookies: "Show cookies ({count})",
      noCookies: "This category currently contains no cookies.",
      cookieName: "Cookie",
      cookieProvider: "Provider",
      cookiePurpose: "Purpose",
      cookieDuration: "Duration",
      firstParty: "this website",
      categories: {
        functionality: {
          title: "Necessary",
          description:
            "Required for the website to work, for example to keep you signed in, protect forms and store your cookie choices."
        },
        performance: {
          title: "Analytics",
          description:
            "Help us understand how visitors use the website, find errors and improve it. The data is collected in aggregate."
        },
        marketing: {
          title: "Marketing",
          description:
            "Used by us and our advertising partners to show you relevant ads and measure the success of our campaigns."
        },
        unknown: {
          title: "Other",
          description: "Cookies we have not categorised yet. They are only set with your consent."
        }
      }
    },
    de: {
      bannerTitle: "Wir verwenden Cookies",
      bannerText:
        "Wir verwenden Cookies und \u00e4hnliche Technologien, um diese Website zu betreiben, ihre Nutzung zu verstehen und f\u00fcr Marketing. " +
        "Sie k\u00f6nnen alle akzeptieren, die optionalen ablehnen oder ausw\u00e4hlen, welche Kategorien Sie erlauben. " +
        "Ihre Auswahl k\u00f6nnen Sie jederzeit in den Cookie-Einstellungen \u00e4ndern.",
      acceptAll: "Alle akzeptieren",
      rejectAll: "Alle ablehnen",
      customize: "Anpassen",
      save: "Auswahl speichern",
      close: "Schlie\u00dfen",
      preferencesTitle: "Cookie-Einstellungen",
      preferencesText:
        "W\u00e4hlen Sie, welche Cookies wir verwenden d\u00fcrfen. Notwendige Cookies sind immer aktiv, da die Website ohne sie nicht funktioniert.",
      privacyPolicy: "Datenschutzerkl\u00e4rung",
      imprint: "Impressum",
      alwaysActive: "Immer aktiv",
      showCookies: "Cookies anzeigen ({count})",
      noCookies: "Diese Kategorie enth\u00e4lt derzeit keine Cookies.",
      cookieName: "Cookie",
      cookieProvider: "Anbieter",
      cookiePurpose: "Zweck",
      cookieDuration: "Speicherdauer",
      firstParty: "diese Website",
      categories: {
        functionality: {
          title: "Notwendig",
          description:
            "Erforderlich, damit die Website funktioniert, zum Beispiel um Sie angemeldet zu halten, Formulare zu sch\u00fctzen und Ihre Cookie-Auswahl zu speichern."
        },
        performance: {
          title: "Statistik",
          description:
            "Helfen uns zu verstehen, wie Besucher die Website nutzen, Fehler zu finden und sie zu verbessern. Die Daten werden zusammengefasst ausgewertet."
        },
        marketing: {
          title: "Marketing",
          description:
            "Werden von uns und unseren Werbepartnern genutzt, um Ihnen relevante Werbung zu zeigen und den Erfolg unserer Kampagnen zu messen."
        },
        unknown: {
          title: "Sonstige",
          description: "Cookies, die wir noch nicht kategorisiert haben. Sie werden nur mit Ihrer Einwilligung gesetzt."
        }
      }
    }
  };

  var DEFAULTS = {
    // Cookies by category, as written by `cookiejar-consent`:
    // { functionality: [{ name, domain, provider, description, duration, party }], ... }
    cookies: null,
    // URL of a JSON file from `cookiejar-consent --format json`, used when no cookies are given.
    cookiesUrl: null,
    // Bump to ask every visitor again, e.g. after adding a new tool.
    revision: 1,
    language: null,
    texts: {},
    privacyPolicyUrl: null,
    imprintUrl: null,
    storage: {
      cookieName: "cookiejar_consent",
      // Set to e.g. "example.com" to share the choice across subdomains.
      cookieDomain: null,
      maxAgeDays: 180
    },
    googleConsentMode: {
      enabled: true,
      // Consent Mode types granted by each category.
      types: {
        functionality: ["functionality_storage", "personalization_storage", "security_storage"],
        performance: ["analytics_storage"],
        marketing: ["ad_storage", "ad_user_data", "ad_personalization"],
        unknown: []
      },
      waitForUpdate: 500,
      adsDataRedaction: true,
      urlPassthrough: false,
      // ISO 3166-2 region codes the defaults apply to; all regions when empty.
      region: []
    },
    // dataLayer event pushed whenever consent is set or loaded.
    dataLayerEvent: "cookie_consent_update",
    // Delete the first-party cookies of a category from the report when its consent is withdrawn.
    deleteCookiesOnWithdraw: true,
    // Reload the page when consent is withdrawn, so tags that already ran stop.
    reloadOnWithdraw: false,
    // URL of a consent log (see receiver/ in the cookiejar repository) that receives a record of every decision.
    recordUrl: null,
    // Show categories without cookies in the settings.
    showEmptyCategories: false,
    // Banner colours etc.: CSS custom properties without the leading "--cj-".
    theme: {}
  };

  // ---------------------------------------------------------------------------
  // Configuration

  function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function merge(target, source) {
    if (!isObject(source)) return target;
    Object.keys(source).forEach(function (key) {
      var value = source[key];
      if (value === undefined) return;
      target[key] = isObject(value) && isObject(target[key]) ? merge(merge({}, target[key]), value) : value;
    });
    return target;
  }

  function scriptAttributes() {
    var script = document.currentScript;
    if (!script) return {};
    var data = script.dataset;
    var options = {};
    if (data.cookiesUrl) options.cookiesUrl = data.cookiesUrl;
    if (data.revision) options.revision = data.revision;
    if (data.language) options.language = data.language;
    if (data.privacyPolicyUrl) options.privacyPolicyUrl = data.privacyPolicyUrl;
    if (data.imprintUrl) options.imprintUrl = data.imprintUrl;
    if (data.cookieDomain) options.storage = { cookieDomain: data.cookieDomain };
    if (data.recordUrl) options.recordUrl = data.recordUrl;
    return options;
  }

  var config = merge(merge(merge(merge({}, DEFAULTS), EMBEDDED_CONFIG), window.cookiejarConsentConfig), scriptAttributes());

  function language() {
    var lang = (config.language || document.documentElement.lang || navigator.language || "en").toLowerCase();
    var base = lang.split("-")[0];
    return TEXTS[lang] ? lang : TEXTS[base] ? base : "en";
  }

  var lang = language();
  // config.texts may hold overrides for all languages ({ acceptAll: "..." }) or per language ({ de: { ... } }).
  var texts = merge(merge(merge({}, TEXTS.en), TEXTS[lang]), config.texts);
  if (isObject(config.texts[lang])) texts = merge(texts, config.texts[lang]);

  function t(key, values) {
    return String(texts[key]).replace(/\{(\w+)\}/g, function (_, name) {
      return values && name in values ? values[name] : "";
    });
  }

  function categoryText(category) {
    return merge(merge({}, TEXTS.en.categories[category]), texts.categories[category]);
  }

  // ---------------------------------------------------------------------------
  // Stored consent

  function readStored() {
    var name = config.storage.cookieName + "=";
    var parts = document.cookie ? document.cookie.split("; ") : [];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].indexOf(name) !== 0) continue;
      try {
        var stored = JSON.parse(decodeURIComponent(parts[i].slice(name.length)));
        if (isObject(stored) && isObject(stored.categories)) return stored;
      } catch (e) {
        // Ignore a damaged cookie; the visitor is asked again.
      }
    }
    return null;
  }

  function writeStored(stored) {
    var cookie =
      config.storage.cookieName + "=" + encodeURIComponent(JSON.stringify(stored)) +
      "; Max-Age=" + Math.round(config.storage.maxAgeDays * 86400) +
      "; Path=/; SameSite=Lax";
    if (config.storage.cookieDomain) cookie += "; Domain=" + config.storage.cookieDomain;
    if (location.protocol === "https:") cookie += "; Secure";
    document.cookie = cookie;
  }

  function randomId() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return Date.now().toString(36) + Math.random().toString(36).slice(2);
  }

  function normalise(categories) {
    var result = {};
    CATEGORIES.forEach(function (category) {
      result[category] = category === REQUIRED || !!(categories && categories[category]);
    });
    return result;
  }

  var stored = readStored();
  var current = stored ? normalise(stored.categories) : null;
  var needsDecision = !stored || String(stored.revision) !== String(config.revision);

  // ---------------------------------------------------------------------------
  // Google Consent Mode and the dataLayer

  window.dataLayer = window.dataLayer || [];
  // gtag() must push the Arguments object, not an array.
  function gtag() {
    window.dataLayer.push(arguments);
  }

  function consentModeState(categories) {
    var state = {};
    var types = config.googleConsentMode.types;
    CATEGORIES.forEach(function (category) {
      (types[category] || []).forEach(function (type) {
        // A type granted by any allowed category stays granted.
        if (state[type] !== "granted") state[type] = categories[category] ? "granted" : "denied";
      });
    });
    return state;
  }

  function setConsentModeDefaults() {
    var gcm = config.googleConsentMode;
    if (!gcm.enabled) return;
    var defaults = consentModeState(normalise(null));
    if (gcm.waitForUpdate) defaults.wait_for_update = gcm.waitForUpdate;
    if (gcm.region && gcm.region.length) defaults.region = gcm.region;
    gtag("consent", "default", defaults);
    if (gcm.adsDataRedaction) gtag("set", "ads_data_redaction", true);
    if (gcm.urlPassthrough) gtag("set", "url_passthrough", true);
  }

  function announce(categories, source) {
    if (config.googleConsentMode.enabled) gtag("consent", "update", consentModeState(categories));
    if (config.dataLayerEvent) {
      window.dataLayer.push({ event: config.dataLayerEvent, cookie_consent: categories, cookie_consent_source: source });
    }
    try {
      document.dispatchEvent(new CustomEvent("cookiejar:consent", { detail: { categories: categories, source: source } }));
    } catch (e) {
      // CustomEvent is unavailable in very old browsers.
    }
    listeners.slice().forEach(function (listener) {
      try {
        listener(categories, source);
      } catch (e) {
        if (window.console) console.error(e);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Scripts and embeds that wait for consent:
  //   <script type="text/plain" data-cookie-category="performance" src="...">
  //   <iframe data-cookie-category="marketing" data-src="..."></iframe>

  function allowed(element) {
    var category = element.getAttribute("data-cookie-category");
    return !!(current && current[category]);
  }

  function activateElements() {
    if (!current) return;
    var scripts = document.querySelectorAll('script[type="text/plain"][data-cookie-category]');
    Array.prototype.forEach.call(scripts, function (original) {
      if (!allowed(original)) return;
      var script = document.createElement("script");
      Array.prototype.forEach.call(original.attributes, function (attribute) {
        if (attribute.name !== "type") script.setAttribute(attribute.name, attribute.value);
      });
      var type = original.getAttribute("data-type");
      if (type) script.type = type;
      if (!original.src) script.text = original.text;
      script.setAttribute("data-cookie-activated", "");
      original.parentNode.replaceChild(script, original);
    });
    var embeds = document.querySelectorAll("[data-cookie-category][data-src]");
    Array.prototype.forEach.call(embeds, function (element) {
      if (!allowed(element)) return;
      element.setAttribute("src", element.getAttribute("data-src"));
      element.removeAttribute("data-src");
    });
  }

  // ---------------------------------------------------------------------------
  // Deleting cookies of withdrawn categories

  function deleteCookie(name, path) {
    var parts = location.hostname.split(".");
    var domains = [""];
    for (var i = 0; i < parts.length - 1; i++) domains.push("; Domain=" + parts.slice(i).join("."));
    var paths = path && path !== "/" ? ["/", path] : ["/"];
    domains.forEach(function (domain) {
      paths.forEach(function (p) {
        document.cookie = name + "=; Max-Age=0; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=" + p + domain;
      });
    });
  }

  function deleteCookies(category) {
    var list = (cookieList && cookieList[category]) || [];
    list.forEach(function (cookie) {
      if (cookie.party === "third" || cookie.name === config.storage.cookieName) return;
      deleteCookie(cookie.name, cookie.path);
    });
  }

  // ---------------------------------------------------------------------------
  // Consent log
  //
  // Each decision is sent as a record, so the site can prove what a visitor
  // agreed to. The body is JSON but sent as text/plain, which needs no CORS
  // preflight, so the log can run on another origin. sendBeacon still delivers
  // when the visitor leaves the page right after deciding.

  var BANNER_VERSION = "1";

  function pageUrl() {
    // Without query and fragment, which can hold personal data.
    return location.protocol + "//" + location.host + location.pathname;
  }

  function record(categories, action) {
    if (!config.recordUrl) return;
    var source = isObject(config.source) ? config.source : {};
    var body = JSON.stringify({
      id: stored.id,
      timestamp: stored.updated,
      action: action,
      categories: categories,
      revision: String(config.revision),
      report: source.report || null,
      fingerprint: source.fingerprint || null,
      url: pageUrl(),
      language: lang,
      bannerVersion: BANNER_VERSION
    });
    try {
      var blob = new Blob([body], { type: "text/plain;charset=UTF-8" });
      if (navigator.sendBeacon && navigator.sendBeacon(config.recordUrl, blob)) return;
      if (window.fetch) {
        fetch(config.recordUrl, { method: "POST", body: body, keepalive: true, credentials: "omit", mode: "no-cors",
                                  headers: { "Content-Type": "text/plain;charset=UTF-8" } })
          .catch(function () {});
      }
    } catch (e) {
      if (window.console) console.warn("cookiejar consent: cannot record consent: " + e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Applying a choice

  var listeners = [];

  function setConsent(categories, source) {
    var next = normalise(categories);
    var withdrawn = current
      ? CATEGORIES.filter(function (category) {
          return current[category] && !next[category];
        })
      : [];
    current = next;
    needsDecision = false;
    stored = { revision: config.revision, id: (stored && stored.id) || randomId(), updated: new Date().toISOString(), categories: next };
    writeStored(stored);
    if (config.deleteCookiesOnWithdraw) {
      CATEGORIES.forEach(function (category) {
        if (!next[category]) deleteCookies(category);
      });
    }
    announce(next, source);
    record(next, source);
    activateElements();
    if (withdrawn.length && config.reloadOnWithdraw) location.reload();
    return next;
  }

  // ---------------------------------------------------------------------------
  // Cookie list

  var cookieList = isObject(config.cookies) ? config.cookies : null;
  var cookieListLoaded;

  function loadCookieList() {
    if (cookieListLoaded) return cookieListLoaded;
    if (cookieList || !config.cookiesUrl || !window.fetch) {
      cookieListLoaded = Promise.resolve(cookieList || {});
    } else {
      cookieListLoaded = fetch(config.cookiesUrl, { credentials: "same-origin" })
        .then(function (response) {
          if (!response.ok) throw new Error("HTTP " + response.status);
          return response.json();
        })
        .then(function (data) {
          cookieList = isObject(data.cookies) ? data.cookies : {};
          return cookieList;
        })
        .catch(function (error) {
          if (window.console) console.warn("cookiejar consent: cannot load " + config.cookiesUrl + ": " + error.message);
          cookieList = {};
          return cookieList;
        });
    }
    return cookieListLoaded;
  }

  function visibleCategories() {
    return CATEGORIES.filter(function (category) {
      var count = ((cookieList && cookieList[category]) || []).length;
      if (category === "unknown") return count > 0;
      return count > 0 || category === REQUIRED || config.showEmptyCategories;
    });
  }

  // ---------------------------------------------------------------------------
  // User interface, rendered in a shadow root so site styles don't leak in.

  var STYLES =
    ":host{all:initial}" +
    "*{box-sizing:border-box}" +
    ".root{--cj-font:system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;--cj-background:#fff;--cj-text:#1d1d1f;" +
    "--cj-muted:#5f6368;--cj-border:#dcdfe3;--cj-accent:#1a56db;--cj-accent-text:#fff;--cj-radius:10px;" +
    "--cj-shadow:0 8px 32px rgba(0,0,0,.18);font:15px/1.5 var(--cj-font);color:var(--cj-text)}" +
    ".banner{position:fixed;z-index:2147483646;left:16px;right:16px;bottom:16px;max-width:880px;margin:0 auto;" +
    "background:var(--cj-background);border:1px solid var(--cj-border);border-radius:var(--cj-radius);" +
    "box-shadow:var(--cj-shadow);padding:20px 24px;max-height:calc(100vh - 32px);overflow:auto}" +
    "h2{font-size:18px;line-height:1.3;margin:0 0 8px;font-weight:650}" +
    "p{margin:0 0 12px}" +
    "a{color:var(--cj-accent)}" +
    ".links{display:flex;gap:16px;flex-wrap:wrap;font-size:14px;margin-bottom:16px}" +
    ".actions{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}" +
    "button{font:inherit;font-weight:600;cursor:pointer;border-radius:8px;padding:9px 18px;" +
    "border:1px solid var(--cj-accent);background:var(--cj-accent);color:var(--cj-accent-text)}" +
    "button.secondary{background:transparent;color:var(--cj-accent)}" +
    "button:focus-visible,summary:focus-visible,input:focus-visible+.switch{outline:2px solid var(--cj-accent);outline-offset:2px}" +
    "dialog{font:inherit;color:inherit;background:var(--cj-background);border:none;border-radius:var(--cj-radius);" +
    "box-shadow:var(--cj-shadow);padding:0;width:min(720px,calc(100vw - 32px));max-height:calc(100vh - 32px)}" +
    "dialog::backdrop{background:rgba(0,0,0,.45)}" +
    ".dialog{display:flex;flex-direction:column;max-height:calc(100vh - 32px)}" +
    ".head{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:20px 24px 0}" +
    ".head h2{margin:0}" +
    ".close{background:transparent;border:none;color:var(--cj-muted);font-size:24px;line-height:1;padding:4px 8px}" +
    ".body{overflow:auto;padding:12px 24px}" +
    ".foot{padding:16px 24px;border-top:1px solid var(--cj-border)}" +
    ".category{border:1px solid var(--cj-border);border-radius:8px;padding:14px 16px;margin-bottom:12px}" +
    ".category-head{display:flex;align-items:center;justify-content:space-between;gap:12px}" +
    ".category h3{font-size:16px;margin:0;font-weight:650}" +
    ".category p{color:var(--cj-muted);font-size:14px;margin:6px 0 0}" +
    ".always{font-size:13px;color:var(--cj-muted);white-space:nowrap}" +
    "label.toggle{position:relative;display:inline-flex;cursor:pointer;flex:none}" +
    "label.toggle input{position:absolute;opacity:0;width:100%;height:100%;margin:0;cursor:pointer}" +
    ".switch{width:44px;height:24px;border-radius:12px;background:#b8bcc2;position:relative;transition:background .15s}" +
    ".switch::after{content:'';position:absolute;top:3px;left:3px;width:18px;height:18px;border-radius:50%;" +
    "background:#fff;transition:transform .15s}" +
    "input:checked+.switch{background:var(--cj-accent)}" +
    "input:checked+.switch::after{transform:translateX(20px)}" +
    "details{margin-top:10px;font-size:14px}" +
    "summary{cursor:pointer;color:var(--cj-accent);font-weight:600}" +
    ".table{overflow-x:auto;margin-top:8px}" +
    "table{border-collapse:collapse;width:100%;font-size:13px}" +
    "th,td{text-align:left;vertical-align:top;padding:6px 8px;border-bottom:1px solid var(--cj-border)}" +
    "th{font-weight:600;white-space:nowrap}" +
    "td.name{font-family:ui-monospace,Menlo,Consolas,monospace;word-break:break-all}" +
    ".empty{color:var(--cj-muted);margin:8px 0 0}" +
    "@media (max-width:560px){.banner{left:8px;right:8px;bottom:8px;padding:16px}.actions button{flex:1 1 100%}}" +
    "@media (prefers-reduced-motion:reduce){.switch,.switch::after{transition:none}}";

  var host, root, banner, dialog;

  function h(tag, attributes, children) {
    var element = document.createElement(tag);
    Object.keys(attributes || {}).forEach(function (key) {
      var value = attributes[key];
      if (value === null || value === undefined || value === false) return;
      if (key.indexOf("on") === 0) element.addEventListener(key.slice(2), value);
      else element.setAttribute(key, value === true ? "" : value);
    });
    (children || []).forEach(function (child) {
      if (child === null || child === undefined || child === false) return;
      element.appendChild(typeof child === "string" ? document.createTextNode(child) : child);
    });
    return element;
  }

  function mount() {
    if (host) return;
    host = h("div", { id: "cookiejar-consent" });
    var shadow = host.attachShadow({ mode: "open" });
    shadow.appendChild(h("style", {}, [STYLES]));
    root = h("div", { class: "root", lang: lang });
    Object.keys(config.theme || {}).forEach(function (key) {
      root.style.setProperty("--cj-" + key, config.theme[key]);
    });
    shadow.appendChild(root);
    document.body.appendChild(host);
  }

  function links() {
    var items = [];
    if (config.privacyPolicyUrl) items.push(h("a", { href: config.privacyPolicyUrl }, [t("privacyPolicy")]));
    if (config.imprintUrl) items.push(h("a", { href: config.imprintUrl }, [t("imprint")]));
    return items.length ? h("div", { class: "links" }, items) : null;
  }

  function acceptAll(source) {
    var all = {};
    CATEGORIES.forEach(function (category) {
      all[category] = true;
    });
    return setConsent(all, source || "accept_all");
  }

  function rejectAll(source) {
    return setConsent({}, source || "reject_all");
  }

  function close() {
    if (banner) {
      banner.remove();
      banner = null;
    }
    if (dialog) {
      if (dialog.open) dialog.close();
      dialog.remove();
      dialog = null;
    }
  }

  // Accept and reject get the same prominence, as data protection authorities require.
  function showBanner() {
    mount();
    close();
    banner = h("section", { class: "banner", role: "region", "aria-label": t("bannerTitle"), "aria-live": "polite" }, [
      h("h2", {}, [t("bannerTitle")]),
      h("p", {}, [t("bannerText")]),
      links(),
      h("div", { class: "actions" }, [
        h("button", { type: "button", class: "secondary", "data-action": "customize", onclick: function () { showPreferences(); } }, [t("customize")]),
        h("button", { type: "button", "data-action": "reject-all", onclick: function () { rejectAll(); close(); } }, [t("rejectAll")]),
        h("button", { type: "button", "data-action": "accept-all", onclick: function () { acceptAll(); close(); } }, [t("acceptAll")])
      ])
    ]);
    root.appendChild(banner);
  }

  function cookieTable(list) {
    var rows = list.map(function (cookie) {
      var provider = cookie.provider || (cookie.party === "first" ? t("firstParty") : cookie.domain);
      return h("tr", {}, [
        h("td", { class: "name" }, [cookie.name]),
        h("td", {}, [provider || ""]),
        h("td", {}, [cookie.description || ""]),
        h("td", {}, [cookie.duration || ""])
      ]);
    });
    return h("div", { class: "table" }, [
      h("table", {}, [
        h("thead", {}, [
          h("tr", {}, [
            h("th", { scope: "col" }, [t("cookieName")]),
            h("th", { scope: "col" }, [t("cookieProvider")]),
            h("th", { scope: "col" }, [t("cookiePurpose")]),
            h("th", { scope: "col" }, [t("cookieDuration")])
          ])
        ]),
        h("tbody", {}, rows)
      ])
    ]);
  }

  function categorySection(category, choice) {
    var text = categoryText(category);
    var list = (cookieList && cookieList[category]) || [];
    var id = "cj-" + category;
    var control =
      category === REQUIRED
        ? h("span", { class: "always" }, [t("alwaysActive")])
        : h("label", { class: "toggle" }, [
            h("input", {
              type: "checkbox",
              role: "switch",
              id: id,
              "data-category": category,
              "aria-labelledby": id + "-title",
              "aria-describedby": id + "-description",
              checked: !!choice[category]
            }),
            h("span", { class: "switch", "aria-hidden": "true" })
          ]);
    return h("section", { class: "category", "data-category": category }, [
      h("div", { class: "category-head" }, [h("h3", { id: id + "-title" }, [text.title]), control]),
      h("p", { id: id + "-description" }, [text.description]),
      list.length
        ? h("details", {}, [h("summary", {}, [t("showCookies", { count: list.length })]), cookieTable(list)])
        : h("p", { class: "empty" }, [t("noCookies")])
    ]);
  }

  function showPreferences() {
    return loadCookieList().then(function () {
      mount();
      close();
      var choice = current || normalise(null);
      var selected = function () {
        var categories = {};
        Array.prototype.forEach.call(dialog.querySelectorAll("input[data-category]"), function (input) {
          categories[input.getAttribute("data-category")] = input.checked;
        });
        return categories;
      };
      var finish = function (apply) {
        apply();
        close();
      };
      dialog = h("dialog", { "aria-labelledby": "cj-preferences-title" }, [
        h("div", { class: "dialog" }, [
          h("div", { class: "head" }, [
            h("h2", { id: "cj-preferences-title" }, [t("preferencesTitle")]),
            h("button", { type: "button", class: "close", "aria-label": t("close"), "data-action": "close", onclick: function () { dialog.close(); } }, ["\u00d7"])
          ]),
          h("div", { class: "body" }, [h("p", {}, [t("preferencesText")]), links()].concat(
            visibleCategories().map(function (category) {
              return categorySection(category, choice);
            })
          )),
          h("div", { class: "foot actions" }, [
            h("button", { type: "button", class: "secondary", "data-action": "save", onclick: function () { finish(function () { setConsent(selected(), "custom"); }); } }, [t("save")]),
            h("button", { type: "button", "data-action": "reject-all", onclick: function () { finish(rejectAll); } }, [t("rejectAll")]),
            h("button", { type: "button", "data-action": "accept-all", onclick: function () { finish(acceptAll); } }, [t("acceptAll")])
          ])
        ])
      ]);
      // Closing without a decision brings the banner back while one is needed.
      dialog.addEventListener("close", function () {
        if (!dialog) return;
        dialog.remove();
        dialog = null;
        if (needsDecision) showBanner();
      });
      root.appendChild(dialog);
      dialog.showModal();
    });
  }

  // ---------------------------------------------------------------------------
  // Public API

  var api = {
    version: BANNER_VERSION,
    config: config,
    getConsent: function () {
      return current ? merge({}, current) : null;
    },
    hasConsent: function (category) {
      return !!(current && current[category]);
    },
    needsDecision: function () {
      return needsDecision;
    },
    acceptAll: function () {
      close();
      return acceptAll("api");
    },
    rejectAll: function () {
      close();
      return rejectAll("api");
    },
    setConsent: function (categories) {
      close();
      return setConsent(categories, "api");
    },
    show: function () {
      onReady(showBanner);
    },
    showPreferences: function () {
      return new Promise(function (resolve) {
        onReady(function () {
          resolve(showPreferences());
        });
      });
    },
    hide: close,
    // Forgets the choice and asks again.
    reset: function () {
      var cookie = config.storage.cookieName + "=; Max-Age=0; Path=/";
      document.cookie = config.storage.cookieDomain ? cookie + "; Domain=" + config.storage.cookieDomain : cookie;
      stored = null;
      current = null;
      needsDecision = true;
      onReady(showBanner);
    },
    // listener(categories, source) is called on every change, and right away if consent is known.
    onChange: function (listener) {
      listeners.push(listener);
      if (current) listener(merge({}, current), "stored");
      return function () {
        listeners = listeners.filter(function (l) {
          return l !== listener;
        });
      };
    },
    getCookies: function () {
      return loadCookieList();
    }
  };

  function onReady(callback) {
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", callback);
    else callback();
  }

  // ---------------------------------------------------------------------------
  // Start

  window.CookiejarConsent = api;
  // The defaults and a stored choice are applied synchronously, before tags load.
  setConsentModeDefaults();
  if (current) announce(current, "stored");

  // Links like <a href="#" data-cookiejar-preferences>Cookie settings</a> open the settings.
  document.addEventListener("click", function (event) {
    var target = event.target && event.target.closest && event.target.closest("[data-cookiejar-preferences]");
    if (!target) return;
    event.preventDefault();
    api.showPreferences();
  });

  onReady(function () {
    activateElements();
    if (needsDecision) showBanner();
    // Load the cookie list early so the settings open immediately.
    loadCookieList();
  });
})(window, document);
