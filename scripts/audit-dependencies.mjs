import { spawnSync } from "node:child_process";

const allowedAdvisories = new Set(["GHSA-FC5Q-39XC-VJPF"]);
const result = spawnSync("npm", ["audit", "--json"], { encoding: "utf8" });

let report;
try {
  report = JSON.parse(result.stdout || "");
} catch {
  process.stderr.write(result.stderr || "npm audit did not return valid JSON.\n");
  process.exit(1);
}

const vulnerabilities = report.vulnerabilities || {};
const allowedPackages = new Set();
const exceptions = [];

for (const [name, vulnerability] of Object.entries(vulnerabilities)) {
  const via = Array.isArray(vulnerability.via) ? vulnerability.via : [];
  const advisoryIds = via
    .filter(item => item && typeof item === "object")
    .map(item => String(item.url || "").match(/GHSA-[a-z0-9-]+/i)?.[0]?.toUpperCase())
    .filter(Boolean);
  const onlyKnownUnfixedAdvisory =
    name === "picomatch" &&
    vulnerability.severity === "high" &&
    advisoryIds.length > 0 &&
    advisoryIds.every(id => allowedAdvisories.has(id));

  if (onlyKnownUnfixedAdvisory) {
    allowedPackages.add(name);
    exceptions.push({ name, advisoryIds });
  }
}

let changed = true;
while (changed) {
  changed = false;
  for (const [name, vulnerability] of Object.entries(vulnerabilities)) {
    if (allowedPackages.has(name) || !["high", "critical"].includes(vulnerability.severity)) continue;
    const via = Array.isArray(vulnerability.via) ? vulnerability.via : [];
    if (via.length > 0 && via.every(item => typeof item === "string" && allowedPackages.has(item))) {
      allowedPackages.add(name);
      exceptions.push({ name, inheritedFrom: via });
      changed = true;
    }
  }
}

const blocking = Object.entries(vulnerabilities)
  .filter(([name, vulnerability]) =>
    ["high", "critical"].includes(vulnerability.severity) && !allowedPackages.has(name)
  );

if (exceptions.length) {
  process.stdout.write(
    "DOCUMENTED EXCEPTION: GHSA-fc5q-39xc-vjpf has no published patched picomatch release; " +
    "only its transitive dependency chain is temporarily allow-listed.\n"
  );
  for (const item of exceptions) process.stdout.write("  " + JSON.stringify(item) + "\n");
}

if (blocking.length) {
  process.stderr.write("Blocking high/critical dependency vulnerabilities:\n");
  for (const [name, vulnerability] of blocking) {
    process.stderr.write("  " + name + " (" + vulnerability.severity + ") via " + JSON.stringify(vulnerability.via) + "\n");
  }
  process.exit(1);
}

const summary = report.metadata?.vulnerabilities || {};
process.stdout.write(
  "Dependency audit passed policy. High: " + (summary.high || 0) +
  ", critical: " + (summary.critical || 0) +
  ", temporarily excepted packages: " + exceptions.length + ".\n"
);
