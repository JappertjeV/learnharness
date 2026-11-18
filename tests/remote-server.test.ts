import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync, existsSync, mkdtempSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { it } from "node:test";
const { readRemoteServer, writeRemoteServer, normalizeServer, safeName, uniqueName, uploadFile, uploadFolder, NAME_RE } =
	createRequire(import.meta.url)("../electron/remote-server.cjs");

function tempDir() {
	return mkdtempSync(path.join(tmpdir(), "lh-remote-"));
}

/** A session whose fetch records each PUT and answers like upload.py. */
function fakeSession(status = 201, body: unknown = { path: "x" }) {
	const puts: { url: string; bytes: number }[] = [];
	return {
		puts,
		fetch: async (url: string, init: { method: string; body: Buffer }) => {
			assert.equal(init.method, "PUT");
			puts.push({ url, bytes: init.body.length });
			return { status, json: async () => body };
		},
	};
}

it("no server.json (or an unusable one) keeps upstream local mode", () => {
	const dir = tempDir();
	try {
		assert.equal(readRemoteServer(dir), null);
		writeFileSync(path.join(dir, "server.json"), "{not json");
		assert.equal(readRemoteServer(dir), null);
		writeFileSync(path.join(dir, "server.json"), JSON.stringify({ url: "http://learn.example.com" }));
		assert.equal(readRemoteServer(dir), null, "plain http is refused: the login is a cookie");
		writeFileSync(path.join(dir, "server.json"), JSON.stringify({ url: " learn.example.com/auth/ " }));
		assert.equal(readRemoteServer(dir), "https://learn.example.com");
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("normalizeServer keeps only an https origin (http only for localhost)", () => {
	assert.equal(normalizeServer("https://Learn.Example.com:8443/x?y"), "https://learn.example.com:8443");
	assert.equal(normalizeServer("http://localhost:3000"), "http://localhost:3000");
	assert.equal(normalizeServer("https://user:pw@learn.example.com"), null);
	assert.equal(normalizeServer("ftp://learn.example.com"), null);
	assert.equal(normalizeServer(""), null);
	assert.equal(normalizeServer(42), null);
});

it("every generated name passes the server's NAME_RE", () => {
	for (const input of ["Foto 1.HEIC", "été/../../etc/passwd", "..hidden", "😀.png", "", "C:\\temp\\a.pdf", "a/"]) {
		assert.match(safeName(input), NAME_RE, input);
		assert.match(uniqueName(input), NAME_RE, input);
		assert.ok(!uniqueName(input).includes(".."), input);
	}
});

it("uploadFile PUTs the bytes to /app-upload/<name> on the server", async () => {
	const dir = tempDir();
	try {
		const file = path.join(dir, "notes.md");
		writeFileSync(file, "hello");
		const ses = fakeSession();
		await uploadFile(ses, "https://learn.example.com", file, "20261118-x-notes.md");
		assert.deepEqual(ses.puts, [{ url: "https://learn.example.com/app-upload/20261118-x-notes.md", bytes: 5 }]);
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("an expired login (redirect to Authelia) is reported as not signed in", async () => {
	const dir = tempDir();
	try {
		const file = path.join(dir, "a.txt");
		writeFileSync(file, "a");
		await assert.rejects(uploadFile(fakeSession(302), "https://learn.example.com", file, "a.txt"), /not signed in/);
		await assert.rejects(uploadFile(fakeSession(409, { error: "already exists" }), "https://learn.example.com", file, "a.txt"), /already exists/);
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("uploadFolder keeps the structure, skips hidden files and returns the agent path", async () => {
	const dir = tempDir();
	try {
		const root = path.join(dir, "Course notes");
		mkdirSync(path.join(root, "week 1"), { recursive: true });
		writeFileSync(path.join(root, "index.md"), "i");
		writeFileSync(path.join(root, "week 1", "les é.txt"), "w");
		writeFileSync(path.join(root, ".DS_Store"), "x");
		const ses = fakeSession();
		const agentPath = await uploadFolder(ses, "https://learn.example.com", root, "20261118-x-Course notes");
		assert.equal(agentPath, "/home/lh/Bijlagen/20261118-x-Course notes");
		assert.deepEqual(ses.puts.map((p) => p.url).sort(), [
			"https://learn.example.com/app-upload/20261118-x-Course%20notes/index.md",
			"https://learn.example.com/app-upload/20261118-x-Course%20notes/week%201/les%20e-.txt",
		]);
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("an empty folder is refused instead of handing the agent a missing path", async () => {
	const dir = tempDir();
	try {
		writeFileSync(path.join(dir, ".hidden"), "x");
		await assert.rejects(uploadFolder(fakeSession(), "https://learn.example.com", dir), /no files/);
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("writeRemoteServer saves a readable server.json (0600) and null goes back to local mode", () => {
	const dir = tempDir();
	try {
		writeRemoteServer(dir, "https://learn.example.com");
		assert.equal(readRemoteServer(dir), "https://learn.example.com");
		assert.equal(statSync(path.join(dir, "server.json")).mode & 0o777, 0o600);
		assert.deepEqual(readdirSync(dir), ["server.json"], "no temp file left behind");
		writeRemoteServer(dir, null);
		assert.equal(existsSync(path.join(dir, "server.json")), false);
		writeRemoteServer(dir, null); // already local: no error
		assert.throws(() => writeRemoteServer(dir, "learn.example.com"), /normalized/);
		assert.throws(() => writeRemoteServer(dir, "http://learn.example.com"), /normalized/);
	} finally { rmSync(dir, { recursive: true, force: true }); }
});

it("the Server Address window is registered in the app menu and only answers its own window", () => {
	const main = readFileSync(new URL("../electron/main.cjs", import.meta.url), "utf8");
	assert.match(main, /label: "Server Address…", click: \(\) => openServerSetup\(\)/);
	assert.match(main, /event\.sender !== win\.webContents\) throw new Error\("Untrusted request\."\)/);
});
