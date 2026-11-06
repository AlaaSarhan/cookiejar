# frozen_string_literal: true

require "json"
require "uri"

module Cookiejar
  # Finds a cookie consent banner on the current page and accepts all cookies,
  # so cookies that are only set after consent show up in the scan.
  #
  # Banners are looked for in the page, in open shadow roots and in iframes
  # (Ferrum disables site isolation, so cross-origin consent frames are
  # scriptable). Strategies, in order, each tried across all frames before the
  # next one:
  # 1. custom CSS selectors (--consent-selector)
  # 2. accept buttons of known consent management platforms
  # 3. visible buttons whose text reads like "accept all" in common languages,
  #    inside something that looks like a consent banner
  #
  # Banners are often injected after the page load event, so the first page of
  # each host is polled for up to `wait` seconds. Later pages on that host are
  # checked once, which also catches banners shown again on some pages.
  class AutoConsent
    POLL_INTERVAL = 0.25

    KNOWN_PLATFORMS = {
      "OneTrust" => ["#onetrust-accept-btn-handler", "#accept-recommended-btn-handler"],
      "Cookiebot" => ["#CybotCookiebotDialogBodyLevelButtonLevelOptinAllowAll",
                      "#CybotCookiebotDialogBodyButtonAccept", "#CybotCookiebotDialogBodyLevelButtonAccept"],
      "Usercentrics" => ['[data-testid="uc-accept-all-button"]', "#uc-btn-accept-banner"],
      "Didomi" => ["#didomi-notice-agree-button"],
      "Quantcast Choice" => ['.qc-cmp2-summary-buttons button[mode="primary"]'],
      "Sourcepoint" => ["button.sp_choice_type_11"],
      "TrustArc" => ["#truste-consent-button"],
      "consentmanager" => [".cmpboxbtnyes"],
      "Google Funding Choices" => [".fc-cta-consent"],
      "CookieYes" => ['[data-cky-tag="accept-button"]', ".cky-btn-accept"],
      "Complianz" => [".cmplz-btn.cmplz-accept"],
      "Borlabs Cookie" => ["[data-cookie-accept-all]", "a._brlbs-btn-accept-all"],
      "Klaro" => [".cm-btn-accept-all"],
      "Osano" => [".osano-cm-accept-all"],
      "Termly" => ['[data-tid="banner-accept"]'],
      "iubenda" => [".iubenda-cs-accept-btn"],
      "CookieFirst" => ['[data-cookiefirst-action="accept"]'],
      "Axeptio" => ["#axeptio_btn_acceptAll"],
      "Cookie Information" => [".coi-banner__accept"],
      "CookieHub" => [".ch2-allow-all-btn"],
      "Cookie Script" => ["#cookiescript_accept"],
      "Civic Cookie Control" => ["#ccc-recommended-settings", "#ccc-notify-accept"],
      "Piwik PRO" => ["#ppms_cm_agree-to-all"],
      "HubSpot" => ["#hs-eu-confirmation-button"],
      "Crownpeak (Evidon)" => ["#_evidon-accept-button"],
      "Cookie Notice (WordPress)" => ["#cn-accept-cookie"],
      "GDPR Cookie Compliance (WordPress)" => [".moove-gdpr-infobar-allow-all"],
      "Shopify" => [".shopify-pc__banner__btn-accept"]
    }.freeze

    # Button texts that accept cookies, in English, German, French, Spanish,
    # Italian, Portuguese, Dutch, Scandinavian, Finnish, Polish, Czech and Russian.
    ACCEPT_PATTERN = '\b(accept|allow|agree|consent|got it|ok|okay|understood)\b|akzeptier|zustimm|zulassen|' \
                     "einverstanden|annehmen|accepter|j'accepte|d'accord|acept|accett|acconsent|aceit|akkoord|" \
                     "accepteer|toestaan|godkänn|acceptera|godta|tillad|hyväksy|akceptuj|zgadzam|přijmout|" \
                     "souhlas|принять|согласен"
    # Texts of buttons that reject, partially accept or open settings.
    REJECT_PATTERN = "reject|decline|deny|refuse|necessary|essential|required|only|without|selection|settings|" \
                     "preferences|customi[sz]e|manage|options|details|more info|learn more|ablehnen|nur |" \
                     "notwendig|erforderlich|ohne|auswahl|einstellungen|refuser|sans|sélection|paramètres|" \
                     "personnaliser|rechazar|sin |selección|configurar|rifiut|senza|selezione|impostazioni|" \
                     "recusar|weiger|alleen|instellingen|neka|avvis|odrzuć|odmítnout|nastavení|отклонить|настро"
    ACCEPT_ALL_PATTERN = '\ball\b|alle|tout|todo|todas|tutt|wszystk|všechn|kaikki|все'
    # Ids, classes and frame URLs of elements that hold consent banners.
    CONTEXT_PATTERN = "cookie|consent|gdpr|dsgvo|datenschutz|privacy|cmp|banner|notice|tracking|truste|didomi|" \
                      "usercentrics|onetrust|sp_message"

    SCRIPT = <<~JS
      (function (cfg) {
        const visible = (el) => {
          if (!el || !el.isConnected || el.disabled) return false;
          const rect = el.getBoundingClientRect();
          if (rect.width < 1 || rect.height < 1) return false;
          const style = getComputedStyle(el);
          return style.visibility !== "hidden" && style.display !== "none" && parseFloat(style.opacity) > 0;
        };
        const roots = [document];
        const walk = (root) => root.querySelectorAll("*").forEach((el) => {
          if (el.shadowRoot) { roots.push(el.shadowRoot); walk(el.shadowRoot); }
        });
        walk(document);
        const queryAll = (selector) => roots.flatMap((root) => {
          try { return Array.from(root.querySelectorAll(selector)); } catch (e) { return []; }
        });
        const click = (el, how) => {
          if (el.scrollIntoView) el.scrollIntoView({ block: "center" });
          el.click();
          return how;
        };
        const firstVisible = (selectors) => {
          for (const selector of selectors) {
            const el = queryAll(selector).find(visible);
            if (el) return [el, selector];
          }
          return null;
        };

        if (cfg.stage === "selectors") {
          const found = firstVisible(cfg.selectors);
          return found ? click(found[0], "selector " + found[1]) : null;
        }

        if (cfg.stage === "platforms") {
          for (const [name, selectors] of Object.entries(cfg.platforms)) {
            const found = firstVisible(selectors);
            if (found) return click(found[0], name + " (" + found[1] + ")");
          }
          return null;
        }

        const accept = new RegExp(cfg.accept, "i");
        const reject = new RegExp(cfg.reject, "i");
        const acceptAll = new RegExp(cfg.acceptAll, "i");
        const context = new RegExp(cfg.context, "i");
        const inConsentFrame = window !== window.top && context.test(location.href + " " + window.name);
        const looksLikeBanner = (el) => {
          for (let node = el, i = 0; node && i < 15; i++) {
            if (node.nodeType === 1) {
              const signature = [node.id, typeof node.className === "string" ? node.className : "",
                                 node.getAttribute("aria-label"), node.getAttribute("data-testid")].join(" ");
              if (context.test(signature)) return true;
              if (node.getAttribute("role") === "dialog" || node.getAttribute("aria-modal") === "true") return true;
              const position = getComputedStyle(node).position;
              if (position === "fixed" || position === "sticky") return true;
            }
            node = node.parentNode || node.host;
          }
          return false;
        };

        let best = null;
        let bestScore = 0;
        const candidates = queryAll('button, a, [role="button"], input[type="button"], input[type="submit"]');
        for (const el of candidates) {
          if (!visible(el)) continue;
          const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").replace(/\\s+/g, " ").trim();
          if (!text || text.length > 50 || !accept.test(text) || reject.test(text)) continue;
          if (!inConsentFrame && !/cookie/i.test(text) && !looksLikeBanner(el)) continue;

          const score = 1 + (acceptAll.test(text) ? 2 : 0) + (/cookie/i.test(text) ? 1 : 0);
          if (score > bestScore) { best = [el, text]; bestScore = score; }
        }
        return best ? click(best[0], 'button "' + best[1] + '"') : null;
      })(__CONFIG__)
    JS

    STAGES = %w[selectors platforms text].freeze

    def initialize(selectors: [], wait: 5.0, logger: nil)
      @selectors = Array(selectors)
      @wait = wait.to_f
      @logger = logger
      @polled_hosts = Set.new
    end

    # Accepts the consent banner on the browser's current page, if any.
    #
    # @param ferrum [Ferrum::Browser]
    # @return [String, nil] how consent was given, nil if no banner was found
    def accept(ferrum)
      deadline = monotonic + (@polled_hosts.add?(host_of(ferrum.current_url)) ? @wait : 0)
      loop do
        found = try_once(ferrum)
        return found if found
        return nil if monotonic >= deadline

        sleep(POLL_INTERVAL)
      end
    end

    private

    def try_once(ferrum)
      STAGES.each do |stage|
        next if stage == "selectors" && @selectors.empty?

        script = SCRIPT.sub("__CONFIG__") { JSON.generate(config_for(stage)) }
        ferrum.frames.each do |frame|
          # Frames without a JS context (still loading or detached) would block until the page timeout.
          next unless frame.execution_id

          found = begin
            frame.evaluate(script)
          rescue Ferrum::Error
            nil
          end
          next unless found

          return frame.main? ? found : "#{found} in frame #{frame_url(frame)}"
        end
      end
      nil
    end

    def config_for(stage)
      {
        stage: stage, selectors: @selectors, platforms: KNOWN_PLATFORMS, accept: ACCEPT_PATTERN,
        reject: REJECT_PATTERN, acceptAll: ACCEPT_ALL_PATTERN, context: CONTEXT_PATTERN
      }
    end

    def frame_url(frame)
      frame.url
    rescue Ferrum::Error
      frame.name || frame.id
    end

    def host_of(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
