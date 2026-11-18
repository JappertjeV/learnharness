// Regressietest voor safeName in bridge.js: elke naam moet door NAME_RE van de uploaddienst
// (server/upload.py) en mag geen ".." of "/" bevatten.
// Aanleiding: "été/../../etc/passwd" leverde eerst "e-te-.-..etcpasswd" op (server: 400).
//   node ios/scripts/test-bridge.mjs
import fs from "node:fs";
const src = fs.readFileSync(new URL("../LearnHarness/Resources/bridge.js", import.meta.url), "utf8");
const body = src.match(/function safeName\(name\) \{[\s\S]*?\n\t\}/)[0];
const safeName = new Function("return " + body.replace(/^\t/gm, ""))();
const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._ ()+-]{0,180}$/;
const cases = ["Foto 1.HEIC", "été/../../etc/passwd", "..hidden", "rapport (v2).pdf", "😀.png", "",
	"a".repeat(300) + ".txt", "x...y..z", "C:\\temp\\a.pdf", "noext.", "a/b/c.tar.gz"];
let failed = 0;
for (const n of cases) {
	const out = "20261117-230000-ab12-" + safeName(n);
	const ok = NAME_RE.test(out) && !out.includes("..") && !out.includes("/");
	if (!ok) { failed++; console.log("FOUT", JSON.stringify(n), "→", out); }
}
console.log(failed ? `${failed} fout` : `ok (${cases.length} namen)`);
process.exit(failed ? 1 : 0);
