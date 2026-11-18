# Dependency audit exception

## GHSA-fc5q-39xc-vjpf — picomatch

The 2026-11-18 CI run reported the GitHub advisory GHSA-fc5q-39xc-vjpf through the Vite development/build dependency tree: picomatch, fdir, tinyglobby and Vite.

At review time the advisory lists picomatch versions through 4.0.7 as affected but does not identify a patched release. The dependency chain is part of the build toolchain; it is not shipped as application browser code. The CI audit policy therefore temporarily permits only this exact high-severity advisory and packages whose complete reported vulnerability path is through that already-permitted package.

This is an exception, not a remediation or a claim that the advisory is false. The audit still fails on every other high/critical finding, and the exception must be removed as soon as an upstream patched release and compatible dependency update are available. Do not use force upgrades or disable npm audit to clear this finding.

Review source: https://github.com/advisories/GHSA-fc5q-39xc-vjpf
