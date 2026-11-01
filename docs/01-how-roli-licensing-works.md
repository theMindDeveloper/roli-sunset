# 01 — How ROLI's Licensing Actually Works

*Read this first. Everything else (the patch, the walkthrough) builds on understanding this. No prior knowledge assumed — every term is explained when it first appears.*

---

## The big picture

ROLI sells software (synths, drum machines, a "player" for their sound library) that is **licensed** rather than sold outright: the software periodically asks ROLI's servers "is this user allowed to use this?" and only opens up if the answer is yes.

When ROLI's company stopped operating, those servers were switched off. The software kept asking a question that no one answers anymore — so it locked up, even on machines where the customer had fully paid.

This document explains **exactly** what the software checks, and why that matters for what a fix must look like.

## The cast of characters

| Name | What it is |
|------|-----------|
| **ROLI Connect** | A desktop app (written in a web technology called **Electron** — more on that below). It's the "hub": it does the login, talks to the servers, and distributes the license info to the other apps. |
| **Equator2** | A synthesizer (native Windows program, a `.exe`, plus a `.vst3` version that runs inside music DAWs like Ableton or FL Studio). |
| **ROLI Studio Player** | The sound-library player (same: `.exe` + `.vst3`). |
| **ROLI Studio Drums** | The drum machine (same: `.exe` + `.vst3`). |
| **api.roli.com** | ROLI's licensing server. **This is the part that is dead.** |

"Native" means the app is compiled machine code (x86-64) — it runs directly on the CPU. An Electron app is essentially a web page (HTML/JS/CSS) running inside a Chromium browser shell.

## The login flow (what used to happen)

```
┌─────────────┐        ┌──────────────────────────────┐        ┌────────────────┐
│  ROLI       │        │       api.roli.com           │        │  ROLI          │
│  Connect    │        │  (ROLI's licensing server)   │        │  keyboard/PC   │
│  (Electron) │        └──────────────────────────────┘        │                │
└─────────────┘                                                 └────────────────┘
     │  1. user enters email + password
     ├──────────────────────────────────────────────────►
     │  2. server checks the account, sees which products
     │     this user is entitled to, and sends back a TOKEN
     ◄──────────────────────────────────────────────────┤
     │
     │  3. Connect stores the token (in its own settings)
     │
     │  4. Connect starts a tiny local "proxy" service:
     │     a named pipe + a localhost port.
     │     The plugin apps talk to THIS, not to the internet.
     │
     │  5. whenever Equator2/Player/Drums start, they ask the
     │     local proxy:  "GET /api/v1/user/"
     │                   "GET /api/v1/user/entitlements/"
     │     The proxy forwards those to api.roli.com (attaching
     │     the token), gets the answer, and — crucially —
     │     SAVES A COPY of the answer to a file on disk:
     │
     │        %APPDATA%\ROLI\Shared\%2Fapi%2Fv1%2Fuser%2F.json
     │        %APPDATA%\ROLI\Shared\%2Fapi\2Fv1%2Fuser%2Fentitlements%2F.json
     │
     │  6. the plugin apps read that file.
```

Two facts fall out of this diagram, and they are the whole game:

1. **The plugins don't talk to the internet directly.** They read a local file that ROLI Connect filled in. (If Connect is running, they ask the proxy; the proxy fills the file. If Connect is *not* running, they just read the file from the last time it was filled.)
2. **The file contains a signed answer** — not just "user X may use product Y", but a *cryptographic signature* proving the answer really came from ROLI's server.

## The token: a JWT

The "token" returned by the server is a **JWT** (JSON Web Token). A JWT is a small text blob with three parts separated by dots:

```
eyJhbGciOiJIUzI1NiIs... . eyJ1aWQiOiI...IiwiZXhwIjoxNjAwMDAwMDAwfQ . signature
 header                payload (claims)                    (hmac signature)
```

The middle part, once decoded, is just JSON — it contains claims like:

- `sub` — the user id
- `exp` — an **expiration timestamp** (ROLI issued tokens valid for 30 days)

Think of a JWT as a **paper ticket with a printed expiry date**. The app checks the date *by itself*, on the user's machine. That's why ROLI Connect would nuke the whole license file when the ticket's printed date passed — no server round-trip needed to decide "expired".

## The offline file: what the plugins actually check

This is the important part. The file the plugins read looks (simplified) like:

```json
{
  "headers": {
    "date": "Tue, 27 Oct 2026 05:47:30 GMT",
    "content-type": "application/json",
    "x-message-signature": "MEUCIQ...",
    "x-signer-certificate": "-----BEGIN CERTIFICATE----- ...",
    "x-signer-certificate-signature": "MEUCIQ..."
  },
  "status": 200,
  "body": {
    "uid": "the-user-id",
    "email": "user@example.com",
    "expiration": 1793319028,
    "entitlements": [ { "name": "Equator2", "enabled": true }, ... ]
  }
}
```

When a plugin (say Equator2) starts up offline, its native code does this:

```
1. Read the .json file.
2. Is status == 200?                         (did the "server" say OK?)
3. Is body.expiration still in the future?   (is the ticket unexpired?)
4. Verify the SIGNATURE CHAIN:
     x-message-signature          ← signs the body (the actual data)
     x-signer-certificate         ← the "signer's" certificate
     x-signer-certificate-signature ← signs the certificate itself
     and that last signature is checked against a ROOT PUBLIC KEY
     that is compiled into the .exe itself.
5. If ALL of that passes → "licensed". Otherwise → lock the app.
```

Step 4 is a **public-key signature chain** (Ed25519-style, the same family of math used in SSH keys). To put it in plain language:

> ROLI's server signs its answers with a secret **private** key. Every plugin has the matching **public** key built into it. Math makes it impossible to forge a valid signature without the private key — you can change any byte in the file and the signature check breaks.

This is a **tamper-evident seal**: you can open and re-seal the package in any way you like, but the app can tell the seal isn't the original one.

**Consequence:** you cannot fix this by *editing the JSON file* — you'd have to also forge the signature, which is impossible without ROLI's private signing key, which was on the dead servers (or their hardware) and is not publicly available.

That single fact is what forces the entire solution in this repo to be a **binary patch** instead of a "config file fix". More in doc 02.

## The root key, for reference

The public root key is embedded as a 32-byte value in each plugin binary. Base64, as it appears in the files:

```
RWTVpFS7WTTlDkLcLodJHUodFa8zi/Nboe+KK83CLQycsOUtVYgJyN9Q
```

It is *public* material (it ships inside every copy of the software you legally own), not a secret. Knowing it lets you **verify** signatures; it cannot be used to **create** them.

## Why "just log in" doesn't work, and why a patch is the only option

| Idea | Why it fails |
|------|--------------|
| Log in with my old ROLI account | `api.roli.com` is offline. There is nothing to log into. |
| Edit the JSON file to set expiration far in the future | The signature check (step 4 above) fails on any modified file. |
| Re-create the JSON with my own signature | You'd need ROLI's private key. It doesn't exist anywhere we can reach. |
| Run a fake ROLI server and point the app at it | Same problem: the fake server can't produce valid signatures, and the app is built to check them. |
| **Patch the check itself** | The check is a few hundred lines of code *inside the .exe on your disk*. You own that file. Changing its bytes is the only route that needs no dead server and no lost key. |

That last row is this project.

## One more detail: the 2-week re-check

Some apps (Equator2) store `lastCheckedAuthTime` in `%APPDATA%\Equator2\Equator2.shared` and only re-read the license file roughly every two weeks — an optimization so they don't parse the file on every launch. The patch works at a level below that logic, so it doesn't matter, but it explains why "I changed the file and nothing happened" can feel flaky: the app may simply not have looked at the file again yet.

## Glossary (as used in this repo)

- **JWT** — JSON Web Token; a self-contained, signed, expiring credential.
- **Public / private key pair** — two mathematically linked keys: one signs, the other verifies. You can never derive the signer from the verifier.
- **Signature chain** — a signature on the data, plus a signature on the signer's certificate, plus that certificate verified against a trusted root key built into the app.
- **Ed25519** — a modern elliptic-curve signature algorithm (SSH-style).
- **app.asar** — the archive Electron apps bundle their JavaScript into (think of it as a zip the app reads directly).
- **Native binary / .exe / .vst3** — compiled x86-64 machine code.
- **Gatekeeper function** — the single function inside each plugin that answers "is this license valid?" (defined precisely in doc 02).

Next: [02 — the reverse-engineering walkthrough](02-the-reverse-engineering-walkthrough.md)
