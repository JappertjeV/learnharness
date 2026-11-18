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
}
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
	}

	function start() {
		ensureViewport();
		injectStyle();
		new MutationObserver(tick).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["aria-hidden", "role"] });
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
