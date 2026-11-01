# 02 — The Reverse-Engineering Walkthrough

*This is the actual step-by-step of how the patch in this repo was found, designed, and proven. Written so you can follow every decision. If a term is unknown, doc 01 or doc 03 defines it.*

---

## The ground rules we worked by

Before touching anything:

1. **Observe before you modify.** Find out what the system does, with what evidence, before changing a single byte.
2. **Prove each link in the chain.** Every claim ("the plugin checks the signature", "this function is the gate") must have an experiment that would fail if the claim were wrong.
3. **Change the minimum.** The smallest change that achieves the goal, applied at the most robust point.
4. **Everything reversible.** Backups before writes; a documented restore path.

The work happened in nine phases.

---

## Phase 0 — Inventory: what is actually on the machine?

First question: what files make up "ROLI software" here?

```powershell
Get-ChildItem "C:\Program Files\ROLI" -Directory
Get-ChildItem "C:\Program Files\Common Files\VST3" -Directory | Where-Object Name -match 'ROLI|Equator'
```

Findings:

```
C:\Program Files\ROLI\ROLI Connect\        ← Electron app ("roli-hub")
C:\Program Files\ROLI\Equator2\Equator2.exe
C:\Program Files\ROLI\ROLI Studio Player\ROLI Studio Player.exe
C:\Program Files\ROLI\ROLI Studio Drums\ROLI Studio Drums.exe
C:\Program Files\Common Files\VST3\Equator2.vst3
C:\Program Files\Common Files\VST3\ROLI Studio Player.vst3\Contents\x86_64-win\ROLI Studio Player.vst3
C:\Program Files\Common Files\VST3\ROLI Studio Drums.vst3\Contents\x86_64-win\ROLI Studio Drums.vst3
```

Plus the runtime license file the apps read:

```
%APPDATA%\ROLI\Shared\%2Fapi%2Fv1%2Fuser%2F.json
%APPDATA%\ROLI\Shared\%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json
```

(That `%2F` is URL-encoded `/` — the app names its local cache files after the API paths it cached. Good clue: it means these files are **cached HTTP responses**.)

**Lesson:** start with a plain inventory. The file *names* already told us the licensing data flows from HTTP endpoints into local files.

---

## Phase 1 — Read the Electron app (the easy 80%)

Electron apps bundle their code in `resources\app.asar` — essentially a zip. We extracted it with the official tool:

```
npm i -g @electron/asar
asar extract "C:\Program Files\ROLI\ROLI Connect\resources\app.asar" work\app
```

Inside: `main.prod.js` (the "main process" — runs with full system privileges) and `dist\renderer.prod.js` (the UI code, bundled/minified but still *readable JavaScript*).

Searching the readable code for the interesting strings:

```
rg "authenticate" work\app
rg "entitlements" work\app
rg "x-access-token" work\app
```

This revealed the whole license pipeline (details in doc 01):

- **Login:** `POST https://api.roli.com/api/v1/authenticate/roli-hub` → returns a JWT.
- **Token storage:** renderer stores it in `localStorage` under key `token`; the renderer also **decodes the JWT itself** and compares `exp` to the clock — on expiry it calls `unsetToken()`.
- **IPC:** the main process holds the real token and runs a local proxy (a named pipe `\\.\pipe\roli_connect_ipc_<USERNAME>` plus `127.0.0.1:25438`).
- **Proxy behavior:** plugins ask it for `GET /api/v1/user/` and `GET /api/v1/user/entitlements/`. The proxy forwards to `api.roli.com` with an `x-access-token` header, and **writes the response to the `%APPDATA%\ROLI\Shared\...json` cache files** (with the response *headers* included — that's where the signature headers live).
- **The wipe:** when the token is unset, `clearCache()` deletes the cross-app cache files — so the plugins instantly see "no license".

Two conclusions:

1. The *Connect* side is pure JavaScript we can read line-by-line.
2. The *plugin* side (native code) is what we still have to reverse.

---

## Phase 2 — Prove the license flow empirically (the test matrix)

No patch design should start from disassembly alone. We first pinned down, with experiments, exactly which file and which fields the plugins enforce.

**Experiment A — baseline (does the signed file work offline?):**

- Stop ROLI Connect. No ROLI servers reachable (they're dead anyway).
- Keep the *original* signed cache files (produced by the live server before shutdown — valid signature, unexpired at the time).
- Launch Equator2.

Result: **fully unlocked.** → *Proof: plugins verify the local file on their own, offline. The file is the license.*

**Experiment B — does it check the expiration, or the signature (or both)?**

- Take the original file, **strip the three signature headers**, set `expiration` far in the future.
- Launch Equator2.

Result: **locked.** → *Proof: editing the file does not work; the signature is enforced. This is the step that kills every "just edit the JSON" idea.*

**Experiment C — control (does the original still pass?):** restore original files → unlocked again. Confirms the lock in B was caused by our edit, not by the environment.

The matrix so far:

| files state | signature | expiration | result |
|---|---|---|---|
| A: original | valid | valid | **unlocked** |
| B: forged | missing | far future | **locked** |
| C: original again | valid | valid | **unlocked** |

That three-row table is the foundation. It says: *the check is real, it's local, and it's cryptographic.* So the fix must be inside the checking code itself.

**Lesson:** the test matrix comes *before* the patch. It tells you what "success" means and gives you a regression test for everything that follows.

---

## Phase 3 — Disassemble the native plugin

Tools: **radare2** (command-line disassembler/hex editor; the same class of tool as Ghidra). Files are x86-64 Windows PE executables.

```
r2 -dC  (or)  r2 Equator2.exe
> i~struct|ls          # list imports/sections
> / strings            # search for strings
```

The search strings came straight from the JSON file structure:

```
/x x-message-signature
/x x-signer-certificate
/x entitlements
/x expiration
```

And the base64 root public key from doc 01:

```
/x RWTVpFS7WTTlDkLcLodJHUodFa8zi/Nboe+KK83CLQycsOUtVYgJyN9Q
```

That root key string appears **exactly once** in each binary — and cross-referencing its usage leads to the verification function. Following the call chain upward from there, everything funnels into **one function** that is called right after the cache file is parsed. *That* function is the **gatekeeper**:

- **size:** 1934 bytes
- **input:** pointer (in register `rcx`, per the Windows x64 calling convention) to a struct holding the parsed HTTP response
- **what it does, in order:**
  1. `cmp dword [rcx], 0xC8` — is the HTTP status `200`? (`0xC8` = 200)
  2. pull out the `x-message-signature`, `x-signer-certificate`, `x-signer-certificate-signature` headers
  3. verify the certificate chain against the embedded root key (a helper at a fixed address, e.g. `fcn.180830b10` in one build)
  4. parse `body.expiration`, compare against the current time
  5. verify the body's message signature
  6. return `1` in `al` (i.e. `eax`/`rax`) if everything passed, `0` otherwise
- **callers:** the "am I licensed?" decision in the app. Everyone who cares asks *this* function.

**Lesson:** start from *data* (the strings that appear in the license file), not from *code*. Strings are the handholds; control flow is the destination. One unique string → one xref → the function you need.

---

## Phase 4 — Design the patch

Goal: make the gatekeeper always answer "valid". Options, in order of badness:

| Option | Why not |
|--------|---------|
| Patch every internal check (status cmp, signature call, time cmp) | 4+ edits, fragile, easy to get one wrong |
| Patch each *caller* to ignore the return value | many call sites, and they live in different functions per build |
| **Patch the gatekeeper's entry: "return 1 immediately"** | One 6-byte edit, at one point, below all the internal checks |

Chosen: overwrite the first 6 bytes of the gatekeeper with:

```asm
mov eax, 1    ; B8 01 00 00 00   — put "valid" in the return register
ret           ; C3               — return to the caller
```

Bytes: **`B8 01 00 00 00 C3`**

Why this is safe and minimal:

- On Windows x64, a function's return value comes back in `rax`. Setting `eax = 1` and returning is exactly "I did the check, the answer is *valid*".
- The original prologue (saving registers, allocating stack) is never executed, so no state is touched — no cleanup, no side effects.
- Every caller, in every build, sees the same answer: `1`.
- 6 bytes. The smallest possible patch.

**Lesson:** patch *semantics*, not symptoms. "Always return valid" expressed at the function boundary is one edit instead of four, and it's provably equivalent for every caller.

---

## Phase 5 — Make the patch location-robust (pattern scanning)

A naive patch would hardcode "write 6 bytes at file offset `0x723050`". That breaks if ROLI ever shipped a different build, a different install layout, or a 32-bit variant. Instead, the patcher **finds** the function by its content:

1. **Unique prologue pattern** — the first 32 bytes of the gatekeeper, which turn out to be unique across the whole binary:

   ```
   48 89 5C 24 10  48 89 74 24 18  55  57  41 54  41 56  41 57
   48 8D AC 24 30 FE FF FF  48 81 EC D0 02 00 00 00
   ```

   (In plain x86-64: save the two home-slot arguments, push the non-volatile registers, compute the stack frame, subtract 0x2d0 bytes. It's a standard prologue — but in a 40 MB binary, this exact 32-byte sequence occurs **once**.)

2. **Guard check** — within the next 96 bytes there must be the `cmp [rcx], 0xC8` instruction:

   ```
   81 39 C8 00 00 00
   ```

   This is the "is status 200?" test from Phase 3. It's the fingerprint that says *this* prologue belongs to *the gatekeeper*, not some coincidental 32-byte collision elsewhere.

3. **Decision:**
   - prologue found **and** guard within 96 bytes, exactly **one** such place → patch at the prologue's offset
   - zero such places → report `no-target` (don't touch the file)
   - the first 6 bytes are already `B8 01 00 00 00 C3` → report `already-patched` (idempotent)
   - more than one candidate → report `ambiguous`, patch nothing (fail safe)

The verified offsets on the current install (for reference; the tool doesn't need them):

| binary | file offset of gatekeeper |
|--------|---------------------------|
| `Equator2.exe` | `0x723050` |
| `Equator2.vst3` | `0x757af0` |
| `ROLI Studio Player.exe` | `0xed7380` |
| `ROLI Studio Player.vst3` | `0xf24e70` |
| `ROLI Studio Drums.exe` | `0xda81a0` |
| `ROLI Studio Drums.vst3` | `0xdf5c10` |

Notice: the *same* function (same bytes, same logic) appears in all six binaries — ROLI built the plugins from one shared codebase — which is why one pattern works for all of them. (File offset ≠ virtual address; the exe/vst3 files have different section layouts, so the offset differs per file even for identical code.)

**Lesson:** never hardcode what you can *recognize*. A pattern + a confirming guard byte makes the tool survive re-builds and different install paths, and it fails safe when unsure.

---

## Phase 6 — Patch the Electron side (app.asar)

The Connect app has two behaviors that break the offline setup, both in `main.prod.js` inside `app.asar`:

1. **`unsetToken()` wipes the cache files** — so if Connect ever runs and sees an expired/missing token, it deletes the very file the plugins rely on.
   The code:
   ```js
   clearCache(e){ this.proxies.local.clearCrossAppCache(), this.proxies.local.cache.clear((e=>{if(e)throw e})) }
   ```
2. **Expired token → hard reset of the login state** in a way that cascades into (1).

The trick: **`app.asar` is just a concatenation of files with a header; every file's length is recorded.** If you replace a piece of code with *exactly the same number of bytes*, the archive stays 100% structurally valid and you don't even need to repack it — you edit bytes in place.

So both edits are **same-length string replacements**:

| original (minified JS) | replacement | effect |
|---|---|---|
| `clearCache(e){this.proxies.local.clearCrossAppCache(),this.proxies.local.cache.clear((e=>{if(e)throw e}))}` | `clearCache(e){}` + spaces to fill the rest | cache-clearing becomes a no-op; the offline file survives |
| `void this.unsetToken(e)` | `e(null,t,r)` + spaces | when the login flow resolves without a token, continue with a null user instead of tearing state down |

Each replacement is padded with spaces (valid inside a JS block body only as harmless whitespace at statement level — the minified context makes it a no-op statement) so **length in = length out**. The patcher verifies the needle occurs exactly once before writing, and reports `already patched` on re-runs.

**Lesson:** format constraints (here: asar's length header) can be *your friend* — same-length edits let you patch an archive without re-creating it, which is simpler and safer.

---

## Phase 7 — The offline license file

The plugins still *read* a license file — the patch only changes what they do with it. So we ship a **permanent offline license file** with the structure the original files had, minus anything that could expire or identify a person:

- `status: 200`
- `body.uid`: neutral id (`000000000000000000000000`)
- `body.email`: empty
- `body.expiration`: `4102444800` (year 2100)
- all `entitlements` present with `enabled: true`
- **signature headers removed** (they'd be invalid for our file anyway; the patched gatekeeper never looks at them)

The file is embedded in the patcher script as base64 (one dependency-free file) and written to the two `%APPDATA%\ROLI\Shared\...json` paths after backing up whatever was there.

**Lesson:** patch the *check*, but still provide *data*. The app expects a file to exist; leave it expecting a real-looking one.

---

## Phase 8 — Package it as a tool, not a script fragment

Requirements that turned the lab script into the customer tool:

1. **Self-elevation** — writing to `C:\Program Files` needs admin; the script detects it and re-launches itself elevated.
2. **Backup everything first** — each modified file is copied to `%LOCALAPPDATA%\ROLI-Sunset\backup\<timestamp>...` and recorded in a `manifest.csv` (original path, backup path, type). Nothing is overwritten before its backup exists.
3. **`-Restore`** — walks the manifest, copies originals back, byte-for-byte.
4. **`-DryRun`** — does everything except writes; prints what *would* happen.
5. **Idempotency** — re-running reports `already-patched` / `already patched` / `no-change` instead of corrupting or double-patching.
6. **Fail-safe scanning** — scan by *content pattern*, patch only on a unique + guarded match, refuse on ambiguity.
7. **Single file, zero dependencies** — one `.ps1` that runs on stock Windows PowerShell 5.1.

---

## Phase 9 — End-to-end verification

The full proof, run on a real machine with the real install:

| step | expected | observed |
|------|----------|----------|
| Run patcher (elevated) | 6 binaries patched at the offsets in Phase 5, asar patched (2 edits), 2 cache files installed, all backed up | exactly that; log shows each `patch @ 0x...` and `DONE` |
| Re-run patcher | everything reports `already-patched` / `no-change` | yes |
| Launch Equator2 (no Connect running) | full synth UI, no license screen | yes (screenshot in `assets/`) |
| Launch ROLI Studio Player | full UI + sound library | yes (screenshot in `assets/`) |
| Launch ROLI Studio Drums | full UI, pads/macros | yes (screenshot in `assets/`) |
| Reboot, repeat launches | still unlocked | yes |
| `-Restore` | originals byte-identical, offline file gone | verified with checksums |
| Re-run patcher after restore | patches cleanly again | yes |

**Lesson:** a patch isn't done when it *works once*; it's done when it works on re-run, survives reboot, and undoes cleanly. That's the whole Phase 9 table.

---

## What we deliberately did NOT do

- **macOS builds** — different binaries (Mach-O), different paths; the same *method* applies but the patterns/offsets must be redone.
- **Auto-updater** — ROLI Connect still checks GitHub Releases for updates; if a new roli-hub ever appears, the asar edits would need re-applying (the binary patches are independent).
- **Signing the tool** — an Authenticode-signed build of the patcher would calm SmartScreen; not done (no certificate available).
- **Recovering server-side content** — cloud presets/accounts are gone; no tool can bring data back from dead servers.

## The whole thing, compressed to the essence

1. Read the readable parts (Electron = JS).
2. Prove the offline license is a *signed local file* (3 experiments).
3. Find the native check via its data strings → one 1934-byte gatekeeper function.
4. Patch its entry: `mov eax,1; ret` (6 bytes, "always valid").
5. Locate it by unique prologue + guard byte (no hardcoded offsets).
6. Same-length JS edits in the asar so Connect stops wiping the file.
7. Ship a permanent, neutral, non-expiring offline file.
8. Wrap in backup/restore/dry-run/idempotency.
9. Prove the matrix: fresh run, re-run, reboot, restore, re-run.
