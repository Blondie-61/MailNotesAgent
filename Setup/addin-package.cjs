const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const manifestName = "addin-build.json";
function files(directory, prefix = "") {
  return fs.readdirSync(path.join(directory, prefix), { withFileTypes: true })
    .filter(entry => ![".git", ".DAV", ".DS_Store"].includes(entry.name) && !entry.name.startsWith("._"))
    .sort((a, b) => a.name.localeCompare(b.name))
    .flatMap(entry => {
      const name = prefix + entry.name;
      if (entry.isSymbolicLink()) throw Error("Symlink im Build: " + name);
      return entry.isDirectory() ? files(directory, name + "/") : [name];
    });
}
function digest(file) {
  return crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
}
function checkReferences(directory) {
  for (const name of ["taskpane.html", "taskpane.js", "commands.html", "commands.js", "polyfill.js", "manifest.xml"]) {
    if (!fs.existsSync(path.join(directory, name))) throw Error("Build-Datei fehlt: " + name);
  }
  for (const name of files(directory).filter(name => /\.html$/.test(name))) {
    const html = fs.readFileSync(path.join(directory, name), "utf8");
    for (const match of html.matchAll(/\b(?:src|href)=["']([^"']+)["']/g)) {
      const reference = match[1].split(/[?#]/)[0];
      if (!reference || /^(?:[a-z]+:|\/\/|#)/i.test(reference)) continue;
      const resolved = path.resolve(directory, path.dirname(name), decodeURIComponent(reference));
      if (!resolved.startsWith(path.resolve(directory) + path.sep) || !fs.existsSync(resolved))
        throw Error("Fehlende/ungueltige HTML-Referenz: " + name + " -> " + reference);
    }
  }
}
function seal(directory) {
  checkReferences(directory);
  const entries = files(directory).filter(name => name !== manifestName)
    .map(name => ({ path: name, sha256: digest(path.join(directory, name)) }));
  const manifest = { version: 1, files: entries };
  manifest.buildId = crypto.createHash("sha256").update(JSON.stringify(entries)).digest("hex");
  fs.writeFileSync(path.join(directory, manifestName), JSON.stringify(manifest, null, 2) + "\n");
  validate(directory);
}
function validate(directory) {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, manifestName), "utf8"));
  if (manifest.version !== 1 || !Array.isArray(manifest.files) || manifest.files.length === 0)
    throw Error("Ungueltiges Add-in-Buildmanifest");
  const names = new Set();
  for (const entry of manifest.files) {
    if (!/^[a-zA-Z0-9_.\/-]+$/.test(entry.path) || entry.path.split("/").some(p => !p || p === "." || p === "..") ||
        entry.path === manifestName || names.has(entry.path) || !/^[a-f0-9]{64}$/.test(entry.sha256))
      throw Error("Ungueltiger Build-Eintrag");
    names.add(entry.path);
    if (digest(path.join(directory, entry.path)) !== entry.sha256) throw Error("Build-Pruefsumme falsch: " + entry.path);
  }
  const actual = files(directory).filter(name => name !== manifestName);
  if (actual.length !== names.size || actual.some(name => !names.has(name))) throw Error("Unerwartete Dateien im Build");
  const id = crypto.createHash("sha256").update(JSON.stringify(manifest.files)).digest("hex");
  if (id !== manifest.buildId) throw Error("Build-ID falsch");
  checkReferences(directory);
  return manifest;
}
function deploy(source, destination) {
  source = path.resolve(source);
  destination = path.resolve(destination);
  const nested = (a, b) => a === b || a.startsWith(b + path.sep);
  if (nested(source, destination) || nested(destination, source)) throw Error("Quell- und Zielordner ueberlappen");
  validate(source);
  const staging = destination + ".staging";
  const rollback = destination + ".rollback";
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  if (fs.existsSync(staging)) throw Error("Staging vorhanden: " + destination);
  let moved = false;
  // Claim staging before entering cleanup, so another deployment's files
  // are preserved if exclusive directory creation fails.
  fs.mkdirSync(staging);
  try {
    for (const name of files(source)) {
      const destinationFile = path.join(staging, name);
      fs.mkdirSync(path.dirname(destinationFile), { recursive: true });
      fs.copyFileSync(path.join(source, name), destinationFile, fs.constants.COPYFILE_EXCL);
    }
    validate(staging);
    if (fs.existsSync(rollback)) {
      // Der macOS-Agent behält das vorige Paket regulär als Rollback.
      // Erst ein vollständig gültiges Live-Paket erlaubt dessen Ablösung.
      validate(destination);
      fs.rmSync(rollback, { recursive: true });
    }
    if (fs.existsSync(destination)) {
      fs.renameSync(destination, rollback);
      moved = true;
    }
    try {
      fs.renameSync(staging, destination);
    } catch (error) {
      if (moved) fs.renameSync(rollback, destination);
      throw error;
    }
  } finally {
    if (fs.existsSync(staging)) fs.rmSync(staging, { recursive: true });
  }
  if (moved) fs.rmSync(rollback, { recursive: true });
}
module.exports = { seal, validate, deploy };
if (require.main === module) {
  try {
    const [command, source, destination] = process.argv.slice(2);
    if (command === "seal") seal(source);
    else if (command === "validate") validate(source);
    else if (command === "deploy") deploy(source, destination);
    else throw Error("Aufruf: addin-package.cjs seal|validate|deploy Quelle [Ziel]");
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

