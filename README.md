# Kunji

**Find every cryptographic key and algorithm an organisation depends on, score its quantum risk, and plan the
post-quantum migration.** *Kunji* (कुंजी) is Hindi for "key".

Kunji is an enterprise cryptographic discovery and analysis tool. It scans source code, binaries, certificates,
server configurations, container images and live TLS / SSH endpoints, and produces:

- a **CycloneDX 1.6 Cryptographic Bill of Materials** (CBOM, ECMA-424), checked against the official schema;
- a **quantum-risk score per algorithm and per certificate**, from Mosca's inequality with a probabilistic
  quantum-computer arrival curve, separating harvest-now-decrypt-later from forge-later risk;
- a **compliance date** per asset: the earlier of NIST IR 8547 and India's DST / National Quantum Mission roadmap;
- **protocol-correct replacements** (for example `mlkem768x25519-sha256` for SSH, `X25519MLKEM768` for TLS 1.3,
  ML-KEM as an additional IKEv2 key exchange), with their latency and size cost measured on your own hardware;
- a **PQ-hybrid fallback check**: systems that offer a post-quantum key exchange but still accept classical ones;
- an offline **HTML dashboard**, **SARIF** for code-scanning tools, JSON, and a CI gate (`--fail-on`).

Built by Team Orchestra for Smart India Hackathon 2026, problem statement SIH26164 (NTRO): *Enterprise Cryptographic
Discovery & Analysis Tool*.

![Kunji dashboard: real scan of paramiko](examples/output/paramiko/dashboard.png)

*Real scan of [paramiko](https://github.com/paramiko/paramiko) @142f593, production code only.*

## Quick start

```bash
git clone https://github.com/PiyushIsCoding/kunji && cd kunji
pip install .                      # Python 3.10+; installs the kunji command
kunji scan examples/demo-bank -o out/   # writes out/cbom.json, report.html, report.sarif, report.json
```

Scan anything, or several things into one CBOM:

```bash
kunji scan ./service                         # source tree: code, configs, certificates, keys, binaries
kunji scan app.tar                           # container image from `docker save` or an OCI layout tarball
kunji scan tls://api.example.com:443         # live TLS endpoint (also host:port, https://...)
kunji scan ssh://bastion.example.com:22      # live SSH endpoint
kunji scan ./service app.tar api.example.com:443 --name payments -o out/
kunji scan . --fail-on critical              # CI gate: exit code 3 when anything is CRITICAL
kunji bench                                  # latency and wire size: classical vs post-quantum, on this machine
kunji rules                                  # the algorithm knowledge base
```

Risk inputs you can set: `--shelf-life` (years data must stay secret, default 10), `--anchor-life` (years a
signature must stay trusted, default 5), `--sector cii|enterprise` (which India roadmap dates apply).

For air-gapped sites: `docker build -t kunji .` once, carry the image in, run with `--network none` for code and
image scans.

## What it looks at

| Sensor | Finds | How |
|---|---|---|
| `source` | crypto API calls and algorithm names in Python, Java, Go, C/C++, JS/TS, Rust, C#, Ruby, PHP, Kotlin, Swift, Scala and config formats | pattern rules over code lines only (comments, docstrings, tests, docs and vendored code are skipped, so counts reflect what ships); SSH algorithm preference lists |
| `certificate` | X.509 certificates, private keys committed to the tree, SSH public keys, PKCS#12 | parses PEM / DER / OpenSSH / PKCS#12 with `cryptography`; key type and size, signature hash, validity, CA flag, ML-DSA certificates |
| `config` | what servers will negotiate | OpenSSH `sshd_config`, nginx, Apache httpd, HAProxy, `openssl.cnf`, strongSwan `ipsec.conf` / `swanctl.conf` (incl. RFC 9370 `ke1_mlkem768`) |
| `binary` | crypto compiled into executables, libraries and JARs | algorithm constants (AES S-box, SHA-2 K, ML-KEM / ML-DSA NTT tables ...), crypto API identifiers, OpenSSL / Go / liboqs version and PQ capability |
| `container` | everything above inside an image | safe layer-by-layer extraction (whiteouts, no symlinks, path-traversal guard), package database (dpkg / apk) for OpenSSL and OpenSSH versions |
| `network` | what a live endpoint actually accepts | SSH: server `KEXINIT` lists; TLS: handshake + certificate, protocol versions, and TLS 1.3 named-group probing with raw ClientHellos (detects `X25519MLKEM768` and the server's preferred group without needing OpenSSL 3.5) |

Every finding keeps its evidence (`file:line`, `image!path` or `host:port`). When more than one sensor sees the same
algorithm, its confidence goes up.

## How the risk is scored

Mosca's inequality: data or trust protected today is exposed if **X + Y > Z**.

- **X**: how long it must stay secret (key exchange, key transport) or trusted (signatures, trust anchors).
  Certificates use their real remaining validity, at least `--anchor-life` for CAs.
- **Y**: how long migrating this asset will take, estimated from how widely it is used (a range).
- **Z**: when a cryptographically relevant quantum computer (CRQC) arrives. Not one year: a probability curve
  interpolated from the Global Risk Institute *Quantum Threat Timeline Report 2025* (28–49 % within 10 years,
  51–70 % within 15 years).

Each Shor-broken asset gets **P(CRQC arrives before X + Y)**:

| Level | Rule |
|---|---|
| CRITICAL | P ≥ 65 %, or P ≥ 50 % for key establishment (harvest-now-decrypt-later) |
| HIGH | P ≥ 35 % |
| MEDIUM | other Shor-broken (RSA, ECC, DH, EdDSA) |
| FIX NOW | broken today without any quantum computer (MD5, SHA-1, 3DES, RC4, DSA, RSA < 2048 certificates and key files, MD5 / SHA-1 signed certificates) |
| LOW | Grover-margin symmetric (AES-128) and legacy-but-unbroken (HMAC-SHA1) |
| SAFE | AES-256, SHA-2/3, ML-KEM, ML-DSA, SLH-DSA, LMS / XMSS |

Compliance date: NIST IR 8547 (ipd) deprecates 112-bit RSA / ECC after 2030 and disallows all of it after 2035;
India's DST / NQM roadmap (May 2026) sets earlier dates for critical information infrastructure (`--sector cii`).
The report shows the earlier of the two.

## Example results

Reproduce with `kunji scan <path> -o out/`. Outputs are committed under [`examples/output/`](examples/output/).

| Target | What it found |
|---|---|
| [paramiko](https://github.com/paramiko/paramiko) @142f593: 53 production files, 19.3k lines, scanned in 0.3 s | 216 crypto uses in 16 algorithm families, 29 of them key exchanges exposed to harvest-now-decrypt-later. The ML-KEM hybrid `mlkem768x25519-sha256` is preferred first, but 7 classical key exchanges stay negotiable, so any peer without PQ support falls back. 5 deprecated algorithms are still offered: `ssh-rsa`, `ssh-rsa-cert-v01@openssh.com`, `3des-cbc`, `hmac-md5`, `hmac-md5-96`. [Dashboard](examples/output/paramiko/report.html) · [CBOM](examples/output/paramiko/cbom.json) · [SARIF](examples/output/paramiko/report.sarif) |
| [`examples/demo-bank`](examples/demo-bank): Python, Go and Java code, nginx / OpenSSH / strongSwan configs, 3 certificates | 47 uses in 17 families. nginx prefers `X25519MLKEM768` but still accepts X25519, P-256, TLS 1.0 and 3DES; SSH and IPsec offer no PQ key exchange and IPsec still allows `modp1024`. The RSA-4096 root CA valid to 2045 is CRITICAL (67 % chance a CRQC arrives before it expires), the expired RSA-1024 gateway certificate is FIX NOW, the ML-DSA-65 pilot certificate is SAFE. [Dashboard](examples/output/demo-bank/report.html) · [CBOM](examples/output/demo-bank/cbom.json) |

GitHub shows `report.html` as source; download it (or the whole `examples/output` folder) and open it in a browser.

## Repository layout

```
kunji/
  sensors/      source, certs, config, binary, container, network (observe only)
  rules.py      algorithm knowledge base: patterns, quantum family, protocol-correct replacement
  risk.py       Mosca scoring, compliance dates, PQ-hybrid fallback detector
  cbom.py       CycloneDX 1.6 CBOM builder + schema validation
  bench.py      classical vs post-quantum latency and size
  report/       HTML dashboard, SARIF
  cli.py        kunji command
examples/       demo-bank sample service, committed scan outputs
tests/          pytest suite (no network needed: local servers and generated fixtures)
```

## Status and roadmap

This is the hackathon prototype (v0.3). Planned for the finale and after:

- HSM / cloud KMS inventory (PKCS#11, read-only), JKS keystores, live IKEv2 probing;
- AST-level reachability (tree-sitter) to tell used crypto from dead code;
- interactive web GUI with a migration board, PostgreSQL history and a dependency graph;
- PDF report and a readiness score per business unit.

Known limits today: source detection is pattern-based (it can over- or under-count unusual code); binary detection
finds algorithms that are compiled in, not whether they are called; TLS 1.2 cipher-suite enumeration is opt-in
(`--deep`) and slow; a TLS-inspecting proxy between Kunji and an endpoint is what gets measured.

## References

- NIST FIPS 203 (ML-KEM), FIPS 204 (ML-DSA), FIPS 205 (SLH-DSA), SP 800-208 (LMS / XMSS), IR 8547 ipd (transition)
- CycloneDX 1.6 / ECMA-424 cryptography properties
- M. Mosca, "Cybersecurity in an Era with Quantum Computers: Will We Be Ready?", IEEE S&P 16(5), 2018
- Global Risk Institute, Quantum Threat Timeline Report 2025
- IETF: hybrid ML-KEM key agreement for TLS 1.3 (X25519MLKEM768), `mlkem768x25519-sha256` for SSH, RFC 9370
  (multiple key exchanges in IKEv2)

## License

Apache-2.0. Team Orchestra, SIH 2026 (team ID 177246).
