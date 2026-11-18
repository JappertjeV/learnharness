"use strict";
/*
 * Remote-server mode (fork addition, 2026-11-18): the desktop shell opens a
 * LearnHarness server elsewhere instead of spawning its own on 127.0.0.1.
 * Why: the same sessions and knowledge graph on the Mac and the iOS app,
 * without syncing a local data dir. The server is the ios/server/ setup
 * (Caddy + Authelia + LearnHarness + upload.py).
 *
 * Opt-in: a file `server.json` in userData — {"url": "https://learn.example.com"}.
 * Without it the shell behaves exactly like upstream.
 *
 * Attachments: the renderer's paperclip hands the agent a FILE PATH. On a
 * remote server a Mac path means nothing, so in this mode every attachment
 * is first uploaded to the server's /app-upload/ (behind the same login)
 * and the agent gets the server-side path — the iOS app's approach.
 */
const fs = require("node:fs");
const path = require("node:path");

const CONFIG_FILE = "server.json";
// Where upload.py stores files, as seen by the agent inside the server.
const AGENT_DIR = "/home/lh/Bijlagen";
// Mirrors NAME_RE and the limits in ios/server/upload.py — keep in sync.
const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._ ()+-]{0,180}$/;
const MAX_FILE_BYTES = 50 * 1024 * 1024;
const MAX_FOLDER_FILES = 500;
const MAX_FOLDER_BYTES = 250 * 1024 * 1024;
const MAX_DEPTH = 8;

/** The configured server origin, or null (= upstream local mode).
 *  https only — the login is a cookie; plain http only for localhost testing. */
function readRemoteServer(userDataDir) {
	let raw;
	try {
		raw = JSON.parse(fs.readFileSync(path.join(userDataDir, CONFIG_FILE), "utf8"));
	} catch {
		return null;
	}
	return normalizeServer(raw?.url);
}

function normalizeServer(input) {
	if (typeof input !== "string" || !input.trim()) return null;
	let text = input.trim();
	if (!text.includes("://")) text = `https://${text}`;
	let url;
	try {
		url = new URL(text);
	} catch {
		return null;
	}
	const local = url.hostname === "localhost" || url.hostname === "127.0.0.1";
	if (url.protocol !== "https:" && !(url.protocol === "http:" && local)) return null;
	if (url.username || url.password) return null;
	return url.origin;
}

/** One path segment the server accepts (NAME_RE), from any file name. */
function safeName(name) {
	const clean = (s) => s.normalize("NFKD").replace(/[^A-Za-z0-9._ ()+-]+/g, "-");
	const plain = String(name).split(/[\\/]/).pop() || "";
	const dot = plain.lastIndexOf(".");
	const ext = dot > 0 ? "." + plain.slice(dot + 1).replace(/[^A-Za-z0-9]/g, "").slice(0, 12) : "";
	const base = clean(dot > 0 ? plain.slice(0, dot) : plain).replace(/\.{2,}/g, ".").replace(/^[^A-Za-z0-9]+/, "").slice(0, 80) || "attachment";
	return (base + (ext.length > 1 ? ext : "")).replace(/\.{2,}/g, ".");
}

function stamp(date = new Date()) {
	const p = (n) => String(n).padStart(2, "0");
	return `${date.getFullYear()}${p(date.getMonth() + 1)}${p(date.getDate())}-${p(date.getHours())}${p(date.getMinutes())}${p(date.getSeconds())}`;
}

/** A unique top-level name, so two uploads never collide (the server never overwrites). */
function uniqueName(name) {
	return `${stamp()}-${Math.random().toString(36).slice(2, 6)}-${safeName(name)}`;
}

async function put(ses, origin, parts, body) {
	if (!parts.every((p) => NAME_RE.test(p) && !p.includes(".."))) throw new Error("invalid file name");
	const target = `${origin}/app-upload/${parts.map(encodeURIComponent).join("/")}`;
	// session.fetch carries the window's login cookie (same session).
	const res = await ses.fetch(target, { method: "PUT", body, redirect: "manual" });
	if (res.status === 201) return;
	let msg = `HTTP ${res.status}`;
	if (res.status >= 300 && res.status < 400) msg = "not signed in (the server redirected to its login)";
	else {
		try { msg = (await res.json()).error || msg; } catch { /* keep the status */ }
	}
	throw new Error(msg);
}

/** Uploads one local file under `name` (already unique and safe). */
async function uploadFile(ses, origin, localPath, name) {
	const stat = await fs.promises.stat(localPath);
	if (!stat.isFile()) throw new Error("not a file");
	if (stat.size > MAX_FILE_BYTES) throw new Error("larger than 50 MB");
	await put(ses, origin, [name], await fs.promises.readFile(localPath));
}

/** Uploads a whole folder (hidden files and symlinks skipped) as `top` and
 *  returns the server-side folder path for the agent. */
async function uploadFolder(ses, origin, localDir, top = uniqueName(path.basename(localDir))) {
	const files = [];
	let total = 0;
	const walk = async (dir, rel) => {
		if (rel.length >= MAX_DEPTH) return;
		for (const entry of await fs.promises.readdir(dir, { withFileTypes: true })) {
			if (entry.name.startsWith(".")) continue;
			const full = path.join(dir, entry.name);
			if (entry.isDirectory()) await walk(full, [...rel, safeName(entry.name)]);
			else if (entry.isFile()) {
				const { size } = await fs.promises.stat(full);
				total += size;
				files.push({ full, parts: [...rel, safeName(entry.name)], size });
				if (files.length > MAX_FOLDER_FILES) throw new Error(`more than ${MAX_FOLDER_FILES} files`);
				if (total > MAX_FOLDER_BYTES) throw new Error("folder larger than 250 MB");
			}
		}
	};
	await walk(localDir, []);
	// An empty folder would give the agent a path that doesn't exist on the server.
	if (files.length === 0) throw new Error("the folder has no files (hidden files are skipped)");
	for (const f of files) {
		if (f.size > MAX_FILE_BYTES) throw new Error(`${f.parts.join("/")}: larger than 50 MB`);
		await put(ses, origin, [top, ...f.parts], await fs.promises.readFile(f.full));
	}
	return `${AGENT_DIR}/${top}`;
}

module.exports = { readRemoteServer, normalizeServer, safeName, uniqueName, uploadFile, uploadFolder, AGENT_DIR, NAME_RE };
