const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.join(__dirname, "..");
const updater = path.join(repoRoot, "src", "update-asar-integrity.ps1");

function createSyntheticAsar(filePath, headerText) {
  const header = Buffer.from(headerText, "utf8");
  const paddedLength = Math.ceil(header.length / 4) * 4;
  const headerPickleSize = 8 + paddedLength;
  const archive = Buffer.alloc(8 + headerPickleSize);

  archive.writeUInt32LE(4, 0);
  archive.writeUInt32LE(headerPickleSize, 4);
  archive.writeUInt32LE(4 + paddedLength, 8);
  archive.writeUInt32LE(header.length, 12);
  header.copy(archive, 16);
  fs.writeFileSync(filePath, archive);
}

function headerHash(headerText) {
  return crypto.createHash("sha256").update(headerText).digest("hex");
}

function runUpdater(sourceAsar, patchedAsar, runtime, extraArgs = []) {
  return childProcess.spawnSync(
    "powershell.exe",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      updater,
      "-SourceAsarPath",
      sourceAsar,
      "-PatchedAsarPath",
      patchedAsar,
      "-RuntimeExecutablePath",
      runtime,
      "-OutputJson",
      ...extraArgs,
    ],
    { encoding: "utf8" }
  );
}

const testRoot = fs.mkdtempSync(
  path.join(os.tmpdir(), "codex-rtl-asar-integrity-")
);

try {
  const sourceAsar = path.join(testRoot, "source.asar");
  const patchedAsar = path.join(testRoot, "patched.asar");
  const runtime = path.join(testRoot, "ChatGPT.exe");
  const sourceHeader = JSON.stringify({ files: { original: { size: 1 } } });
  const patchedHeader = JSON.stringify({ files: { patched: { size: 2 } } });
  const sourceHash = headerHash(sourceHeader);
  const patchedHash = headerHash(patchedHeader);

  createSyntheticAsar(sourceAsar, sourceHeader);
  createSyntheticAsar(patchedAsar, patchedHeader);
  fs.writeFileSync(
    runtime,
    Buffer.from(
      `prefix[{"file":"resources\\\\app.asar","alg":"SHA256","value":"${sourceHash}"}]suffix`,
      "ascii"
    )
  );

  const updateResult = runUpdater(sourceAsar, patchedAsar, runtime);
  assert.equal(
    updateResult.status,
    0,
    updateResult.stderr || updateResult.stdout
  );
  const update = JSON.parse(updateResult.stdout.trim());
  assert.equal(update.action, "Updated");
  const updatedRuntime = fs.readFileSync(runtime, "ascii");
  assert.doesNotMatch(updatedRuntime, new RegExp(sourceHash));
  assert.match(updatedRuntime, new RegExp(patchedHash));

  const repeatResult = runUpdater(sourceAsar, patchedAsar, runtime);
  assert.equal(
    repeatResult.status,
    0,
    repeatResult.stderr || repeatResult.stdout
  );
  assert.equal(JSON.parse(repeatResult.stdout.trim()).action, "AlreadyUpdated");

  fs.writeFileSync(
    runtime,
    Buffer.from(
      `prefix[{"file":"resources\\\\app.asar","alg":"SHA256","value":"${sourceHash}"}]suffix`,
      "ascii"
    )
  );
  const dryRunResult = runUpdater(sourceAsar, patchedAsar, runtime, ["-DryRun"]);
  assert.equal(
    dryRunResult.status,
    0,
    dryRunResult.stderr || dryRunResult.stdout
  );
  assert.equal(JSON.parse(dryRunResult.stdout.trim()).action, "WouldUpdate");
  assert.match(fs.readFileSync(runtime, "ascii"), new RegExp(sourceHash));

  fs.writeFileSync(runtime, "runtime without integrity metadata", "ascii");
  const absentResult = runUpdater(sourceAsar, patchedAsar, runtime);
  assert.equal(
    absentResult.status,
    0,
    absentResult.stderr || absentResult.stdout
  );
  assert.equal(
    JSON.parse(absentResult.stdout.trim()).action,
    "IntegrityMetadataNotPresent"
  );

  fs.writeFileSync(runtime, `runtime with unrelated hash ${sourceHash}`, "ascii");
  const unmarkedHashResult = runUpdater(sourceAsar, patchedAsar, runtime);
  assert.notEqual(unmarkedHashResult.status, 0);
  assert.match(
    unmarkedHashResult.stderr,
    /Could not safely identify the embedded ASAR integrity hash/
  );

  fs.writeFileSync(
    runtime,
    `[{"file":"resources\\\\app.asar","alg":"SHA256","value":"${sourceHash}"}]${sourceHash}`,
    "ascii"
  );
  const ambiguousResult = runUpdater(sourceAsar, patchedAsar, runtime);
  assert.notEqual(ambiguousResult.status, 0);
  assert.match(
    ambiguousResult.stderr,
    /Could not safely identify the embedded ASAR integrity hash/
  );
} finally {
  fs.rmSync(testRoot, { recursive: true, force: true });
}

console.log("ASAR integrity updater tests passed.");
