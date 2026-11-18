// Wat de Mac-app via Electron (preload.cjs → window.lh) aan de UI geeft, voor zover het op
// iOS zin heeft: `getPathForFile` (paperclip → Files) en `chooseAttachmentFolder`
// (paperclip → Folder). Upstream roept alle andere window.lh-functies met `?.` aan (updates, zoom,
// ChatGPT-login), dus die mogen ontbreken.
//
// getPathForFile moet synchroon een pad teruggeven. Daarom: pad meteen bepalen, upload
// direct starten naar /app-upload/ (uploaddienst achter de login), en bij een fout de app
// laten waarschuwen. De agent leest het bestand pas als je je bericht verstuurt.
(function () {
	if (window.lh) return;
	const AGENT_DIR = "/home/lh/Bijlagen";
	const pending = new Map();

	// Veilige naam voor de server (moet door NAME_RE in upload.py): geen paden, geen "..".
	function safeName(name) {
		const clean = (s) => s.normalize("NFKD").replace(/[^A-Za-z0-9._ ()+-]+/g, "-");
		const plain = String(name).split(/[\\/]/).pop() || "";
		const dot = plain.lastIndexOf(".");
		const ext = dot > 0 ? "." + plain.slice(dot + 1).replace(/[^A-Za-z0-9]/g, "").slice(0, 12) : "";
		let base = clean(dot > 0 ? plain.slice(0, dot) : plain).replace(/\.{2,}/g, ".").replace(/^[^A-Za-z0-9]+/, "").slice(0, 80) || "bijlage";
		return (base + (ext.length > 1 ? ext : "")).replace(/\.{2,}/g, ".");
	}


	function stamp() {
		const d = new Date(), p = (n) => String(n).padStart(2, "0");
		return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
	}

	function notify(kind, data) {
		try { window.webkit.messageHandlers.lhNative.postMessage(Object.assign({ kind }, data)); } catch (_) {}
	}

	function getPathForFile(file) {
		if (pending.has(file)) return pending.get(file);
		const rand = Math.random().toString(36).slice(2, 6);
		const name = `${stamp()}-${rand}-${safeName(file.name || "bijlage")}`;
		const path = `${AGENT_DIR}/${name}`;
		pending.set(file, path);
		fetch(`/app-upload/${encodeURIComponent(name)}`, { method: "PUT", body: file, credentials: "same-origin" })
			.then(async (r) => {
				if (!r.ok) {
					let msg = `HTTP ${r.status}`;
					try { msg = (await r.json()).error || msg; } catch (_) {}
					notify("uploadFailed", { name: file.name, error: msg });
				}
			})
			.catch((e) => notify("uploadFailed", { name: file.name, error: String(e && e.message || e) }));
		return path;
	}

	// Bestandskiezer: upstream opent verborgen bestandsvelden met input.click() vanuit een menu
	// (paperclip, "Extract files…"); WKWebView op iOS toont daarop niets. Daarom gaat click() op een
	// bestandsveld naar de native kiezer; die geeft de bestanden terug via __lhDeliverFiles, en het
	// veld krijgt een gewone change, precies alsof iOS het zelf had gedaan.
	const fileInputs = new Map();
	// Waar de laatste tik was: daar hoort het keuzemenu van iOS te verschijnen.
	let lastPointer = { x: 0, y: 0 };
	window.addEventListener("pointerdown", (e) => { lastPointer = { x: e.clientX, y: e.clientY }; }, { capture: true, passive: true });
	const nativeClick = HTMLInputElement.prototype.click;
	HTMLInputElement.prototype.click = function () {
		if (this.type !== "file" || !window.webkit?.messageHandlers?.lhNative) return nativeClick.call(this);
		const id = Math.random().toString(36).slice(2);
		fileInputs.set(id, this);
		// webkitdirectory = "Folder" bij Extract files: native een map kiezen, alle bestanden erin.
		notify("pickFiles", { id, multiple: !!this.multiple, directory: !!this.webkitdirectory, accept: this.accept || "", x: lastPointer.x, y: lastPointer.y, w: 1, h: 1 });
	};
	window.__lhDeliverFiles = function (id, files) {
		const input = fileInputs.get(id);
		fileInputs.delete(id);
		if (!input || !input.isConnected || !Array.isArray(files) || files.length === 0) return;
		const dt = new DataTransfer();
		for (const f of files) {
			const bin = atob(f.b64);
			const bytes = new Uint8Array(bin.length);
			for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
			dt.items.add(new File([bytes], f.name, { type: f.type || "application/octet-stream" }));
		}
		input.files = dt.files;
		input.dispatchEvent(new Event("input", { bubbles: true }));
		input.dispatchEvent(new Event("change", { bubbles: true }));
	};

	// Paperclip → Folder (Mac: een map op de schijf). Hier: de app kiest een map in Bestanden,
	// uploadt hem naar /home/lh/Bijlagen/<map>/ en geeft dat pad terug; null = geannuleerd.
	const folderRequests = new Map();
	function chooseAttachmentFolder() {
		return new Promise((resolve) => {
			const id = Math.random().toString(36).slice(2);
			folderRequests.set(id, resolve);
			notify("pickFolder", { id, x: lastPointer.x, y: lastPointer.y });
		});
	}
	window.__lhFolderChosen = function (id, path) {
		const resolve = folderRequests.get(id);
		folderRequests.delete(id);
		if (resolve) resolve(typeof path === "string" && path ? path : null);
	};

	// Instellingen openen vanuit de native toolbar: upstream luistert hiernaar zoals naar het
	// app-menu van de Mac (settings-dialog.tsx: window.lh?.onOpenSettings).
	const settingsListeners = new Set();
	function onOpenSettings(cb) { settingsListeners.add(cb); return () => settingsListeners.delete(cb); }
	window.__lhOpenSettings = function (section) { for (const cb of settingsListeners) cb(section); };

	window.lh = Object.freeze({ platform: "ios", getPathForFile, chooseAttachmentFolder, onOpenSettings });

	// Knop in de (verborgen) web-zijbalk indrukken, bijv. "Background agents".
	window.__lhClickSidebar = function (re) {
		for (const b of document.querySelectorAll("aside.sidebar-motion button")) {
			if (re.test(b.textContent || "")) { b.click(); return true; }
		}
		return false;
	};

	// Route en of er een plan is: de native titel en de knop Plan volgen de pagina.
	let lastRoute = "";
	function postRoute() {
		const path = location.pathname + (location.pathname === "/chat/new" ? location.search : "");
		const plan = !!document.querySelector('[data-testid="plan-chip"]');
		const key = path + "|" + plan;
		if (key === lastRoute) return;
		lastRoute = key;
		notify("route", { path, plan });
	}
	for (const m of ["pushState", "replaceState"]) {
		const orig = history[m];
		history[m] = function () { const r = orig.apply(this, arguments); setTimeout(postRoute, 0); return r; };
	}
	window.addEventListener("popstate", () => setTimeout(postRoute, 0));

	// Themakleuren (Settings → Appearance) naar de app, als "r,g,b". Via een canvas, zodat elk
	// CSS-kleurformaat (hex, rgb, oklch) hetzelfde uitkomt.
	const THEME_VARS = ["background", "foreground", "card", "muted-foreground", "border", "accent", "primary"];
	let lastTheme = "";
	function postTheme() {
		if (!document.body) return;
		const probe = document.createElement("span");
		probe.style.display = "none";
		document.body.appendChild(probe);
		const canvas = document.createElement("canvas");
		canvas.width = canvas.height = 1;
		const ctx = canvas.getContext("2d", { willReadFrequently: true });
		const vars = {};
		for (const name of THEME_VARS) {
			probe.style.color = `var(--${name})`;
			const css = getComputedStyle(probe).color;
			if (!css || !ctx) continue;
			ctx.clearRect(0, 0, 1, 1);
			ctx.fillStyle = "#000";
			ctx.fillStyle = css;
			ctx.fillRect(0, 0, 1, 1);
			const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
			vars[name] = `${r},${g},${b}`;
		}
		probe.remove();
		const key = JSON.stringify(vars);
		if (key === lastTheme) return;
		lastTheme = key;
		notify("theme", { vars });
	}

	// Lijst verversen bij wijzigingen (zelfde kanaal als de UI zelf).
	let changeTimer = 0;
	function chatsChanged() { clearTimeout(changeTimer); changeTimer = setTimeout(() => notify("chatsChanged", {}), 300); }
	function listenEvents() {
		try {
			const es = new EventSource("/api/events");
			for (const t of ["chats-changed", "turn-started", "turn-settled", "record-changed", "activity-changed"]) es.addEventListener(t, chatsChanged);
		} catch (_) {}
	}

	let tickTimer = 0;
	function onDomChange() { clearTimeout(tickTimer); tickTimer = setTimeout(() => { postRoute(); postTheme(); }, 120); }
	function startObservers() {
		new MutationObserver(onDomChange).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ["class", "style", "data-theme", "data-testid"] });
		postRoute();
		postTheme();
		listenEvents();
	}
	if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", startObservers, { once: true });
	else startObservers();

})();
