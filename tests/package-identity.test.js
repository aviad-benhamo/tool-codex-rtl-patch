const assert = require("node:assert/strict");
const childProcess = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.join(__dirname, "..");
const registrar = path.join(
  repoRoot,
  "src",
  "register-rtl-package-identity.ps1"
);
const registrarSource = fs.readFileSync(registrar, "utf8");
const installer = fs.readFileSync(path.join(repoRoot, "install.ps1"), "utf8");
const launcher = fs.readFileSync(
  path.join(repoRoot, "src", "launch-codex.ps1"),
  "utf8"
);
const activator = fs.readFileSync(
  path.join(repoRoot, "src", "activate-chatgpt.ps1"),
  "utf8"
);
const uninstaller = fs.readFileSync(
  path.join(repoRoot, "uninstall.ps1"),
  "utf8"
);

assert.match(registrarSource, /\$PackageName = 'CodexRtl\.Local'/);
assert.match(registrarSource, /uap10:AllowExternalContent>true/);
assert.match(registrarSource, /rescap:Capability Name="runFullTrust"/);
assert.match(registrarSource, /uap10:TrustLevel="mediumIL"/);
assert.match(registrarSource, /uap10:RuntimeBehavior="win32App"/);
assert.match(registrarSource, /packageName="\$PackageName"/);
assert.match(registrarSource, /applicationId="\$ApplicationId"/);
assert.match(registrarSource, /Add-AppxPackage -Path \$packagePath -ExternalLocation \$AppDirectory/);
assert.match(registrarSource, /Remove-AppxPackage -Package \$package\.PackageFullName/);
assert.match(registrarSource, /New-SelfSignedCertificate/);
assert.match(registrarSource, /Cert:\\CurrentUser\\TrustedPeople/);
assert.match(registrarSource, /makeappx\.exe/);
assert.match(registrarSource, /signtool\.exe/);

assert.match(installer, /src\\register-rtl-package-identity\.ps1/);
assert.match(installer, /Registering local package identity/);
assert.match(installer, /rtlAppUserModelId/);
assert.match(
  installer,
  /shell:AppsFolder\\\$\(\$packageIdentityResult\.appUserModelId\)/
);
assert.match(launcher, /function Get-RtlShellTarget/);
assert.match(launcher, /Codex RTL package identity is missing/);
assert.match(launcher, /shell:AppsFolder\\\$appUserModelId/);
assert.doesNotMatch(launcher, /Start-Process -FilePath \$rtlRuntime/);
assert.match(activator, /function Read-RtlAppUserModelId/);
assert.match(activator, /shell:AppsFolder\\\$rtlAppUserModelId/);
assert.match(uninstaller, /CodexRtl\.Local/);
assert.match(uninstaller, /Remove-RtlPackageIdentity/);
assert.match(uninstaller, /rtlIdentityCertificateThumbprint/);

const testRoot = fs.mkdtempSync(path.join(os.tmpdir(), "codex-rtl-identity-"));
try {
  const appDirectory = path.join(testRoot, "app");
  const stateDirectory = path.join(testRoot, "state");
  fs.mkdirSync(appDirectory);
  fs.mkdirSync(stateDirectory);
  fs.writeFileSync(path.join(appDirectory, "ChatGPT.exe"), "test runtime");

  const result = childProcess.spawnSync(
    "powershell.exe",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      registrar,
      "-AppDirectory",
      appDirectory,
      "-StateDirectory",
      stateDirectory,
      "-DryRun",
      "-OutputJson"
    ],
    { encoding: "utf8" }
  );
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const plan = JSON.parse(result.stdout.trim());
  assert.equal(plan.action, "WouldRegister");
  assert.equal(plan.packageName, "CodexRtl.Local");
  assert.equal(plan.applicationId, "App");
  assert.equal(plan.appDirectory, appDirectory);
  assert.match(plan.applicationManifestPath, /ChatGPT\.exe\.manifest$/);
  assert.match(plan.makeAppxPath, /makeappx\.exe$/i);
  assert.match(plan.signToolPath, /signtool\.exe$/i);
  assert.equal(fs.existsSync(path.join(stateDirectory, "package-identity")), false);
} finally {
  fs.rmSync(testRoot, { recursive: true, force: true });
}

console.log("Package identity wiring tests passed.");
