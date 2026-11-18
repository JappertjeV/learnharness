// Aanpassingen voor het smalle buitenscherm van de iPhone Duo (en elk scherm < 640 px).
// Upstream heeft nog geen layout onder 640 px: de Mac-app dwingt dat minimum af via Electron
// (issue #732 in amosblomqvist/learnharness). Boven 640 px (binnenscherm van de Duo) doet dit
// script niets behalve de viewport-tag: dan is het precies de Mac-UI.
//
// Alleen CSS en klikken op bestaande knoppen; geen wijzigingen in de React-state van upstream.
(function () {
	const NARROW = 640;
	const isNarrow = () => window.innerWidth < NARROW;

	// 1. Viewport: zonder deze tag rendert iOS op 980 px en schaalt alles klein.
	// Zoom (⌘+/⌘− zoals in Electron) via de viewport: de pagina wordt opgemaakt op breedte/zoom en
	// dan vergroot. Zo blijft 100dvh precies het scherm; CSS `zoom` duwde de invoerbalk eraf en
	// WKWebView.pageZoom deed niets. De app geeft zoom en de breedte van de WebView door.
	let zoomState = { z: 1, w: 0 };
	function viewportContent() {
		const tail = "viewport-fit=cover, interactive-widget=resizes-content";
		const { z, w } = zoomState;
		if (Math.abs(z - 1) < 0.001 || !w) return "width=device-width, initial-scale=1, maximum-scale=1, " + tail;
		const s = z.toFixed(3);
		return `width=${Math.round(w / z)}, initial-scale=${s}, minimum-scale=${s}, maximum-scale=${s}, ` + tail;
	}
	window.__lhSetZoom = function (z, w) {
		zoomState = { z: Number(z) || 1, w: Number(w) || 0 };
		const meta = document.querySelector('meta[name="viewport"][data-lh-ios]');
		if (meta) meta.content = viewportContent();
	};

	function ensureViewport() {
		if (document.querySelector('meta[name="viewport"][data-lh-ios]')) return;
		for (const m of document.querySelectorAll('meta[name="viewport"]')) m.remove();
		const meta = document.createElement("meta");
		meta.name = "viewport";
		meta.dataset.lhIos = "1";
		meta.content = viewportContent();
		(document.head || document.documentElement).appendChild(meta);
	}

	// 2. De web-zijbalk is vervangen door de native sessielijst: altijd dicht.
	try { localStorage.setItem("lh:sidebar-open", "0"); } catch (_) {}

	const css = `
/* Aanraakscherm: geen hover-hints over toetsenbordcombinaties. */
@media (pointer: coarse) {
	[data-lh-ios-kbdhint] { display: none !important; }
	/* iOS zoomt in op elk invoerveld met tekst kleiner dan 16 px (ondanks maximum-scale=1 in
	   WKWebView), en zoomt daarna niet terug: de hele UI stond scheef na tikken op "Search nodes". */
	input, textarea, select { font-size: max(16px, 1em) !important; }
}
/* Invoerbalk in Liquid Glass-stijl (iOS 26+), in de kleuren van het thema: doorschijnend,
   vervaagd, met een lichtrand bovenin en een capsulevorm; verzendknop rond. */
[data-lh-glass="composer"] {
	background: color-mix(in srgb, var(--card) 58%, transparent) !important;
	-webkit-backdrop-filter: blur(26px) saturate(180%) !important;
	backdrop-filter: blur(26px) saturate(180%) !important;
	border: 1px solid color-mix(in srgb, var(--foreground) 13%, transparent) !important;
	border-radius: 28px !important;
	box-shadow:
		inset 0 1px 0 color-mix(in srgb, #fff 18%, transparent),
		inset 0 -1px 0 color-mix(in srgb, #000 22%, transparent),
		0 14px 34px rgb(0 0 0 / 0.38) !important;
}
[data-lh-glass="composer"] button[type="submit"] { border-radius: 999px !important; }
[data-lh-glass="composer"] [data-testid="attach-files"] { border-radius: 999px !important; }
[data-lh-glass="chip"], [data-testid="home-mode-switch"] {
	background: color-mix(in srgb, var(--card) 52%, transparent) !important;
	-webkit-backdrop-filter: blur(20px) saturate(170%) !important;
	backdrop-filter: blur(20px) saturate(170%) !important;
	border: 1px solid color-mix(in srgb, var(--foreground) 12%, transparent) !important;
	border-radius: 999px !important;
	box-shadow: inset 0 1px 0 color-mix(in srgb, #fff 14%, transparent), 0 6px 18px rgb(0 0 0 / 0.25) !important;
}
[data-testid="home-mode-switch"] > * { border-radius: 999px !important; }
/* Native app: zijbalk, de knoppen om hem te openen/sluiten en de bovenbalk van een les
   (titel, Plan, fase) staan in de native lijst en toolbar. */
aside.sidebar-motion { position: fixed !important; left: -100vw !important; width: 0 !important; visibility: hidden; }
button[aria-label="Open sidebar"], button[aria-label="Close sidebar"], .lh-closed-toggle { display: none !important; }
/* Van de lesbalk blijft over wat native niet heeft: de extractiering (hoeveel van de les nog
   niet in de graaf staat, met Extract) en knoppen van plugins. Die zweven als glazen pil
   rechtsboven; titel, Plan en fase staan in de native toolbar. Eerder verborg dit de hele balk,
   en daarmee ook de ring: een functie die de Mac wel had. */
html[data-lh-route^="/chat/"] header.lh-wco-gutter {
	position: absolute !important; top: 8px !important; right: 10px !important; left: auto !important;
	z-index: 30 !important; width: auto !important; height: auto !important; min-height: 0 !important;
	gap: 10px !important; padding: 6px 8px !important; border: 1px solid color-mix(in srgb, var(--foreground) 12%, transparent) !important;
	border-radius: 999px !important;
	background: color-mix(in srgb, var(--card) 52%, transparent) !important;
	-webkit-backdrop-filter: blur(20px) saturate(170%) !important; backdrop-filter: blur(20px) saturate(170%) !important;
}
html[data-lh-route^="/chat/"] header.lh-wco-gutter :is([data-plugin-chrome-title], [data-testid="plan-chip"], [data-testid="phase-chip"]),
html[data-lh-route^="/chat/"] header.lh-wco-gutter > div.flex-1[aria-hidden="true"] { display: none !important; }
/* Niets over (oefensessie zonder plugins): geen lege pil. Plan blijft klikbaar via .click(). */
html[data-lh-route^="/chat/"] header.lh-wco-gutter:not(:has([data-testid="coverage-ring"], button:not([data-plugin-chrome-title]):not([data-testid="plan-chip"]))) { display: none !important; }
@media (max-width: ${NARROW - 0.02}px) {
	/* Instellingen (upstream: 920 px breed met een menu van 192 px): volledig scherm, menu als
	   horizontale strook bovenaan. */
	.settings-dialog-pop {
		width: 100vw !important; max-width: 100vw !important;
		height: 100dvh !important; max-height: 100dvh !important;
		border-radius: 0 !important; border: 0 !important;
	}
	/* Thema's (theme-cards.tsx, grid-cols-3): bij ~380 px vielen de kleurbolletjes buiten de kaart. */
	.settings-dialog-pop .grid.grid-cols-3 { grid-template-columns: repeat(2, minmax(0, 1fr)) !important; }
	.settings-dialog-pop > div.flex:has(> nav) { flex-direction: column; }
	.settings-dialog-pop nav {
		width: 100% !important; flex-direction: row !important;
		overflow-x: auto; overflow-y: hidden; flex-shrink: 0;
		border-right: 0 !important; border-bottom: 1px solid var(--border);
	}
	.settings-dialog-pop nav > * { flex: 0 0 auto; white-space: nowrap; width: auto !important; }
	/* Zijvraag (gedockt) niet breder dan het scherm. */
	aside.w-\\[22rem\\] { width: 100vw !important; position: fixed !important; inset: 0 0 0 auto; z-index: 55; }
	/* Knoppenbalk van de graaf (zoeken, Chains, Extract, instellingen): laten afbreken in plaats
	   van over de knop "Open sidebar" heen te schuiven. */
	.lh-wco-floating { max-width: calc(100% - 3.75rem) !important; }
	.lh-wco-floating > div.flex { flex-wrap: wrap; justify-content: flex-end; row-gap: 6px; max-width: 100%; }
	/* Dicteerknop kromp tot "D…": eigen regel onder het invoerveld. */
	div.justify-between:has([data-testid="dictation-toggle"]) { flex-wrap: wrap; row-gap: 8px; }
	div.justify-between > div:has(> [data-testid="dictation-toggle"]) { order: 10; flex: 1 0 100%; }
	div.justify-between > div:has(> [data-testid="dictation-toggle"]) > button { height: 2.25rem; }
	/* Grote sessietitel bovenin compacter. */
	.font-title.text-3xl { font-size: 1.35rem !important; }

	/* Vraagkaart (probe, check, recall, plugin-vragen). Op het buitenscherm kregen vraag en
	   antwoorden maar ~40% van de hoogte: de rest ging naar het zekerheidsblok, een denkveld met
	   eigen kopje en brede knop, en de balk met teller, model, effort en dicteren (Jasper,
	   2026-11-18: "niet mooi en veel info"). Hier: compacter, en de balk weg zolang de vraag
	   openstaat. Upstream-markup blijft gelijk; alleen stijl plus één eigen micknop. */
	[data-testid="question-dock"] [data-dock-scroll-area] { padding: 10px 14px 0 !important; }
	/* Labels als "PROBE" en "CONFIDENCE": 11 px en zonder doorzichtigheid. Op 10,5 px met
	   opacity .75 haalde "PROBE" maar ~3,5:1 contrast (critique 2026-11-18). */
	[data-testid="question-dock"] [data-dock-scroll-area] > div:first-child,
	[data-testid="plugin-question-dock"] .space-y-3 > div:first-child {
		font-size: 11px !important; letter-spacing: .06em !important; margin-bottom: 3px !important;
	}
	/* Vraag- en optietekst staan in .lh-prose, dat zelf font-size: var(--lh-prose-size) zet.
	   Een font-size op de omliggende div of knop bereikt die tekst dus niet (dat was de eerste
	   versie hiervan: alles bleef 16/24). Daarom de variabelen zelf hier overschrijven. */
	[data-testid="question-dock"] [data-dock-scroll-area] > div:nth-child(2) {
		--lh-prose-size: 16px; --lh-prose-leading: 1.4; margin-bottom: 10px !important;
	}
	[data-testid="question-dock"] :is([role="radiogroup"], [role="group"]):not([data-lh-ios-conf]) { gap: 6px !important; padding-bottom: 10px !important; }
	/* Elke rij minstens 44 pt hoog (Apple HIG): "I don't know" was 37, een korte optie 42. */
	[data-testid="question-dock"] button[data-kbdrow] {
		--lh-prose-size: 15px; --lh-prose-leading: 1.35;
		min-height: 44px; padding: 11px 12px !important; gap: 10px !important; border-radius: 12px !important;
	}
	[data-testid="question-dock"] button[data-kbdrow] > span:first-child { margin-top: 2px !important; }
	/* Zekerheid: de schuif van upstream (192 x 16 px, duim 16 px) was met één hand nauwelijks te
	   raken, waardoor vaak de standaard 50% meeging. Op het buitenscherm staan daarom zes knoppen
	   met een woord en het percentage (markConfidence hieronder). De schuif blijft in de pagina
	   en krijgt de keuze, zodat upstream precies dezelfde waarde verstuurt. */
	[data-testid="question-dock"] div:has(> [data-lh-ios-conf]) { padding: 8px 12px !important; }
	[data-testid="question-dock"] div:has(> [data-lh-ios-conf]) > div:has(> [data-testid="confidence-track"]) { display: none !important; }
	[data-lh-ios-conf] { display: grid; grid-template-columns: repeat(6, minmax(0, 1fr)); gap: 4px; }
	[data-lh-ios-conf] button {
		height: 44px; min-width: 0; padding: 0 2px; border-radius: 10px;
		display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 2px;
		border: 1px solid color-mix(in srgb, var(--border) 80%, transparent); background: transparent;
		color: var(--muted-foreground); font: 500 13px/1.1 var(--font-prose, system-ui, sans-serif);
		transition: background-color .15s ease-out, border-color .15s ease-out, color .15s ease-out;
	}
	[data-lh-ios-conf] button > span:last-child { font: 400 10.5px/1 var(--font-mono, ui-monospace, monospace); font-variant-numeric: tabular-nums; opacity: .85; }
	/* Gekozen knop in de kleur die upstream voor die stop gebruikt (de schuif zet die als color). */
	[data-lh-ios-conf] button[aria-checked="true"] {
		color: var(--foreground); background: var(--accent);
		border-color: var(--lh-conf-color, var(--primary)); box-shadow: inset 0 -2px 0 var(--lh-conf-color, var(--primary));
	}
	[data-lh-ios-conf] button[aria-checked="true"] > span:last-child { color: var(--lh-conf-color, var(--foreground)); opacity: 1; }
	[data-lh-ios-conf] button:disabled { opacity: .4; }
	/* Denkveld: capsule zoals de chat-invoer, zonder kopje (de placeholder zegt al wat het is).
	   Mic links, verzenden rechts, allebei 44 pt: eerst stonden ze als 36 x 36 met 2 px ertussen
	   naast elkaar, en een gemiste tik op de mic verstuurde het antwoord. */
	:is([data-testid="question-dock"], [data-testid="plugin-question-dock"]) form { padding: 6px 8px 8px !important; }
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) {
		display: flex !important; align-items: flex-end; gap: 4px;
		border-radius: 26px !important; padding: 3px;
	}
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) > div:first-child:not([role="textbox"]) { display: none !important; }
	/* De knoppenrij van upstream oplossen in de capsule, zodat de mic vóór het veld kan staan. */
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) > div:last-child:not([role="textbox"]) { display: contents !important; }
	/* 16 px: iOS zoomt in op elk invoerveld met kleinere tekst (zie de regel bij pointer: coarse). */
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) > [role="textbox"] {
		flex: 1 1 auto; min-width: 0; min-height: 44px !important; max-height: 7.5rem !important;
		padding: 11px 6px !important; font-size: 16px !important; line-height: 1.38 !important;
	}
	/* Lege placeholder op één regel (met …): over twee regels maakte hij het veld 62 px hoog. */
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) > [role="textbox"][data-empty="true"]::before {
		display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
	}
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) button[type="submit"] {
		flex: 0 0 auto; width: 44px !important; height: 44px !important; padding: 0 !important; margin: 0 !important;
		border-radius: 999px !important; font-size: 0 !important; position: relative;
	}
	/* Absoluut gecentreerd: de (onzichtbare) knoptekst blijft een eigen regel in de knop en duwde
	   de pijl anders omhoog. */
	:is([data-testid="thinking-field"], [data-testid="answer-field"]) button[type="submit"]::before {
		content: ""; position: absolute; inset: 0; margin: auto; width: 20px; height: 20px; background: currentColor;
		-webkit-mask: var(--lh-ios-arrow) center / contain no-repeat; mask: var(--lh-ios-arrow) center / contain no-repeat;
	}
	button[data-lh-ios-mic] {
		order: -1; width: 44px; height: 44px; flex: 0 0 auto; display: grid; place-items: center;
		border-radius: 999px; color: var(--muted-foreground); background: transparent; border: 0;
	}
	button[data-lh-ios-mic]:disabled { opacity: .4; }
	button[data-lh-ios-mic] svg { width: 20px; height: 20px; }
	/* De balk onder de kaart (teller, model, effort, dicteren) is tijdens een open vraag weg.
	   Model en effort kiezen kan na het antwoord of op het binnenscherm. Dicteren loopt via de
	   micknop in het denkveld; tijdens het dicteren (Stop en meter) en bij een dicteerfout komt
	   alleen dat deel van de balk terug, want de app toont daar de status en de foutmelding. */
	html[data-lh-question] [data-testid="stats-bar"] { display: none !important; }
	html[data-lh-question]:is([data-lh-dictation="active"], [data-lh-dictation="error"]) [data-testid="stats-bar"] { display: flex !important; }
	html[data-lh-question] [data-testid="stats-bar"] > :not(:has([data-testid="dictation-toggle"])) { display: none !important; }
	html[data-lh-question]:is([data-lh-dictation="active"], [data-lh-dictation="error"]) button[data-lh-ios-mic] { display: none !important; }
}
:root { --lh-ios-arrow: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='M12 19V5M5 12l7-7 7 7'/%3E%3C/svg%3E"); }
`;

	function injectStyle() {
		if (document.getElementById("lh-ios-style")) return;
		const style = document.createElement("style");
		style.id = "lh-ios-style";
		style.textContent = css;
		(document.head || document.documentElement).appendChild(style);
	}

	// Invoerbalk en de knoppen eronder markeren voor de glas-stijl hierboven.
	function markGlass() {
		for (const clip of document.querySelectorAll('[data-testid="attach-files"]')) {
			let shell = clip.parentElement;
			while (shell && !/\brounded-2xl\b/.test(shell.className || "")) shell = shell.parentElement;
			if (shell && shell.dataset.lhGlass !== "composer") shell.dataset.lhGlass = "composer";
		}
		for (const row of document.querySelectorAll('div.justify-between')) {
			if (!row.querySelector('[data-testid="dictation-toggle"]')) continue;
			for (const b of row.querySelectorAll("button")) if (b.dataset.lhGlass !== "chip") b.dataset.lhGlass = "chip";
		}
	}

	function markRoute() { document.documentElement.dataset.lhRoute = location.pathname; }

	// Open vraag op het smalle scherm: de balk onder de kaart gaat dan weg (CSS hierboven), dus
	// het denkveld krijgt een eigen micknop. Die klikt alleen de echte dicteerknop van upstream
	// aan; welk veld de tekst krijgt, bepaalt upstream zelf (bij een open vraag het denkveld).
	const MIC_SVG = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M19 10v1a7 7 0 0 1-14 0v-1M12 18v4"/></svg>';
	function setData(el, key, value) {
		if (value == null) { if (key in el.dataset) delete el.dataset[key]; }
		else if (el.dataset[key] !== value) el.dataset[key] = value;
	}
	function markQuestion() {
		const root = document.documentElement;
		const fields = isNarrow()
			? document.querySelectorAll('[data-testid="question-dock"] form [data-testid], [data-testid="plugin-question-dock"] .dock-variant form [data-testid]')
			: [];
		const open = [...fields].filter((f) => /^(thinking|answer)-field$/.test(f.dataset.testid));
		setData(root, "lhQuestion", open.length ? "1" : null);

		const toggle = document.querySelector('[data-testid="stats-bar"] [data-testid="dictation-toggle"]');
		const failed = /^Dictation failed/.test(toggle?.getAttribute("aria-label") || "");
		const state = document.querySelector('[data-testid="stats-bar"] [data-testid="dictation-bar"]') ? "active" : failed ? "error" : "idle";
		setData(root, "lhDictation", state);

		// Micknoppen opruimen die niet meer in een open vraagveld staan (breed scherm, vraag weg).
		for (const mic of document.querySelectorAll("button[data-lh-ios-mic]")) {
			if (!open.some((f) => f.contains(mic))) mic.remove();
		}
		for (const field of open) {
			const row = field.lastElementChild;
			if (!row || row.getAttribute("role") === "textbox") continue;
			let mic = row.querySelector("button[data-lh-ios-mic]");
			if (!toggle) { mic?.remove(); continue; }
			if (!mic) {
				mic = document.createElement("button");
				mic.type = "button";
				mic.dataset.lhIosMic = "1";
				mic.setAttribute("aria-label", "Start dictation");
				mic.innerHTML = MIC_SVG;
				mic.addEventListener("click", (e) => {
					e.preventDefault();
					document.querySelector('[data-testid="stats-bar"] [data-testid="dictation-toggle"]')?.click();
				});
				row.insertBefore(mic, row.querySelector('button[type="submit"]'));
			}
			if (mic.disabled !== toggle.disabled) mic.disabled = toggle.disabled;
		}
	}

	// Zekerheid als zes knoppen op het buitenscherm (zie de CSS bij "Zekerheid"). De stops zijn
	// die van upstream (CONFIDENCE_STOPS in src/core); de woorden zijn alleen weergave. Een knop
	// zet de waarde op de echte schuif en stuurt een input-event, zodat de onChange van upstream
	// hem afrondt op de stop en verstuurt zoals altijd.
	const CONF_STOPS = [[0, "No"], [30, "Guess"], [50, "Unsure"], [70, "Likely"], [90, "Sure"], [100, "Certain"]];
	const setNativeValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
	function markConfidence() {
		const sliders = isNarrow() ? [...document.querySelectorAll('[data-testid="question-dock"] [data-testid="confidence-slider"]')] : [];
		for (const group of document.querySelectorAll("[data-lh-ios-conf]")) {
			if (!sliders.some((s) => group.parentElement?.contains(s))) group.remove();
		}
		for (const slider of sliders) {
			const box = slider.closest('[data-testid="confidence-track"]')?.parentElement?.parentElement;
			if (!box) continue;
			let group = box.querySelector(":scope > [data-lh-ios-conf]");
			if (!group) {
				group = document.createElement("div");
				group.dataset.lhIosConf = "1";
				group.setAttribute("role", "radiogroup");
				group.setAttribute("aria-label", "Confidence that your answer is right");
				for (const [value, word] of CONF_STOPS) {
					const b = document.createElement("button");
					b.type = "button";
					b.setAttribute("role", "radio");
					b.setAttribute("aria-label", `${word}, ${value} percent`);
					b.dataset.value = String(value);
					b.innerHTML = `<span>${word}</span><span aria-hidden="true">${value}%</span>`;
					b.addEventListener("click", (e) => {
						e.preventDefault();
						const live = box.querySelector('[data-testid="confidence-slider"]');
						if (!live || live.disabled) return;
						setNativeValue.call(live, String(value));
						live.dispatchEvent(new Event("input", { bubbles: true }));
						queueMicrotask(markConfidence);
					});
					group.appendChild(b);
				}
				box.appendChild(group);
			}
			const current = Number(slider.value);
			const color = slider.style.color;
			if (color && group.style.getPropertyValue("--lh-conf-color") !== color) group.style.setProperty("--lh-conf-color", color);
			for (const b of group.children) {
				const on = String(Number(b.dataset.value) === current);
				if (b.getAttribute("aria-checked") !== on) b.setAttribute("aria-checked", on);
				if (b.disabled !== slider.disabled) b.disabled = slider.disabled;
			}
		}
	}

	// Toetsenbordhints ("↵ submits · ⇧↵ newline", ⌘-combinaties) verbergen op aanraakschermen.
	function markKbdHints() {
		for (const el of document.querySelectorAll("span.text-xs, kbd")) {
			if (el.dataset.lhIosKbdhint) continue;
			const t = el.textContent || "";
			if (t.length < 60 && /[↵⌘⇧⌥]/.test(t) && /(submit|newline|send|⌘)/i.test(t)) el.dataset.lhIosKbdhint = "1";
		}
	}

	function tick() {
		markGlass();
		markRoute();
		markKbdHints();
		markQuestion();
		markConfidence();
	}

	function start() {
		ensureViewport();
		injectStyle();
		new MutationObserver(tick).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["aria-hidden", "role", "aria-label", "disabled", "aria-valuetext", "aria-pressed"] });
		window.addEventListener("resize", tick);
		tick();
	}

	// Aanraakscherm: hover-gebeurtenissen niet doorgeven. Upstream toont bij hover een tooltip
	// (Hint); iOS ziet dat als "inhoud verandert bij hover" en gebruikt de eerste tik dan alleen
	// als hover. Gevolg was dat elke knop met een tooltip twee tikken nodig had.
	let lastTouch = 0;
	window.addEventListener("touchstart", () => { lastTouch = Date.now(); }, { capture: true, passive: true });
	for (const type of ["mouseover", "mouseenter", "pointerover", "pointerenter", "mousemove"]) {
		window.addEventListener(type, (e) => {
			if (e.pointerType === "touch" || Date.now() - lastTouch < 800) e.stopImmediatePropagation();
		}, true);
	}

	// Knoppen focus geven bij aanraken, zoals Chrome/Electron doet (waar upstream voor gebouwd
	// is) en iOS niet. Upstream sluit menu's (paperclip, "Extract files…") bij een blur zonder
	// nieuwe focus erbinnen; zonder dit verdween het menu vóór de tik op "Files" telde.
	// WebKit haalt na mousedown de focus van een knop weg (focusout zonder nieuw doel); daarom
	// de standaardactie van mousedown op knoppen annuleren. De click komt gewoon door.
	// Focussen in de bubbelfase, ná de pointerdown-handlers van React: Radix-tooltips openen bij
	// focus, behalve als hun eigen pointerdown al gezien is. In de capture-fase bleef bij elke tik
	// een tooltip ("Graph display settings") hangen. De mousedown-capture vangt het geval op waarin
	// een component de pointerdown niet laat doorbubbelen.
	const focusTarget = (e) => e.target instanceof Element ? e.target.closest("button, [role='menuitem'], [role='option']") : null;
	const focusIt = (e) => {
		const b = focusTarget(e);
		if (b instanceof HTMLElement && document.activeElement !== b) b.focus({ preventScroll: true });
		return b;
	};
	window.addEventListener("pointerdown", focusIt);
	window.addEventListener("mousedown", (e) => { if (focusIt(e)) e.preventDefault(); }, true);

	// iOS schuift de hele pagina omhoog om een veld boven het toetsenbord te houden, en laat
	// die verschuiving staan als het toetsenbord weggaat: de invoerbalk bleef dan ~30 pt te hoog
	// hangen. De UI van upstream scrollt nooit als document (alleen binnen panelen), dus terug
	// naar 0 is altijd goed.
	window.addEventListener("focusout", () => {
		setTimeout(() => {
			const a = document.activeElement;
			const typing = a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA" || a.isContentEditable);
			if (!typing && (window.scrollX || window.scrollY)) window.scrollTo(0, 0);
		}, 250);
	}, true);

	ensureViewport();
	injectStyle();
	if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
	else start();
})();
