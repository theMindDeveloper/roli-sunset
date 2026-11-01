# 03 — A Beginner's Guide to Reverse Engineering

*You don't need to be good at IT to follow this. You need to be willing to read in small steps. This document teaches the concepts used in this project, from the ground up. Read it in order.*

---

## Part 1 — What a program actually is

### 1.1. Everything is bytes

Your computer stores programs as **files**, and files are just sequences of **bytes** (numbers from 0 to 255). A `.exe` file is machine code: a list of byte patterns the CPU understands one at a time.

You can open any file in a **hex editor** and see its raw bytes:

```
offset:  00000000  00000010
bytes:   48 89 5C 24 10 48 89 74 24 18 55 57 41 54 41 56 ...
```

Two ways to read the same bytes:

- as **characters** (if they form text)
- as **CPU instructions** (if they're machine code)

### 1.2. Assembling and disassembling

CPU instructions have names humans use. For example, the bytes `B8 01 00 00 00` mean "put the number 1 into a register called EAX", which engineers write:

```asm
mov eax, 1
```

- **Assembling**: text instructions → bytes.
- **Disassembling**: bytes → text instructions. ← *this is what a disassembler does*

A **disassembler** (Ghidra, radare2, IDA, x64dbg) reads the bytes of a program and renders them as this kind of instruction text, so you can read what the program *does* without having its source code.

### 1.3. Registers: the CPU's scratchpad

A CPU has a handful of fast little storage slots called **registers** (EAX, RCX, RDI, ...). Functions pass arguments in specific registers and put their result back in one — on 64-bit Windows:

- **Argument 1** goes in `RCX`
- **Argument 2** in `RDX`
- **Return value** comes back in `RAX`

That's the entire convention the patch in this project relies on. The gatekeeper function answers "licensed?" with a number in `RAX`: `1` = yes, `0` = no. So "always answer yes" = "put 1 in RAX and return".

```asm
mov eax, 1     ; result: yes
ret            ; go back to whoever asked
```

That's the whole 6-byte patch. There is nothing more to it.

### 1.4. Functions and "the gatekeeper"

Programs are organized into **functions** — named chunks of code that do one job and get called by other code. If you can find *the one function* that decides a thing, you can influence every place that thing matters. In this project that function was the "is this license valid?" checker — called by every part of the app that cares about licensing. One function, one edit, total effect.

**The mindset:** don't fight the app at its symptoms (many screens, many checks). Find the one decision point everything flows through.

---

## Part 2 — How licenses work (the concepts)

### 2.1. Tokens and expiry

A **token** is a digital ticket. A **JWT** (JSON Web Token) is a specific kind: a small text blob whose middle section is plain JSON you can read, containing claims like "user: X" and "expires at: <date>". Apps check the expiry **themselves, locally** — they don't call a server to ask "am I expired?" They just compare the printed date to their clock.

> Analogy: a concert wristband with a printed date. The bouncer at the door just looks at the date on the band.

### 2.2. Digital signatures (the tamper-evident seal)

A **public-key signature** solves "how do I know this file really came from the server and wasn't edited?". It uses a math pair of keys:

- the **private key** (secret, kept by the server) *creates* signatures
- the **public key** (shipped inside every app) *verifies* signatures

Properties:

- if even **one byte** of the signed data changes, verification fails
- you cannot forge a valid signature without the private key
- you cannot turn a public key into a private key (that's the hard math — curves, e.g. Ed25519)

> Analogy: the server waxes a seal in a shape only its private key can produce. The app has a mold (public key) that only the genuine wax fills perfectly. Re-melt and re-pour the data in any way you like — the mold won't fit.

When the server's answer includes a signature and the app's code *checks* it, then **editing the data file is not a fix** — you'd be forging the seal. That's exactly why this project patches the *checker* instead of the *data* (doc 02, Phase 2 proves the check exists, Phase 4 patches it).

### 2.3. Why "patch the check" is a standard technique

When a check (a) lives in code you already legally have on your machine, (b) depends on a service that no longer exists, and (c) the purpose of the check is to re-verify something you already paid for — modifying your own copy's bytes is the direct, minimal, offline fix. It's a normal systems-engineering move: **make the smallest change at the most robust point that restores the intended behavior.**

(Use this judgment carefully — see Part 5 on where this is appropriate.)

---

## Part 3 — The tooling (what people like me actually use)

| Tool | What it is | Used for in this project |
|------|-----------|--------------------------|
| **Ghidra** | Free NSA disassembler/decompiler with a GUI; turns machine code into readable pseudo-C | understanding the gatekeeper function |
| **radare2 (r2)** | Command-line disassembler + hex editor; scriptable; great for automation | finding the patch bytes, verifying offsets, writing the patch in the lab |
| **x64dbg** | GUI debugger for Windows; step through code live, set breakpoints, watch registers | dynamic confirmation of what the function does at runtime |
| **Process Monitor (procmon)** | Windows tool that logs every file/registry/network access a program makes | discovering which license file the plugins actually read, and when |
| **Wireshark** | network packet analyzer | seeing the exact login/API traffic (not needed here — the server was already dead — but standard practice) |
| **@electron/asar** | the official tool to open Electron apps' `app.asar` archive | reading ROLI Connect's JavaScript |
| **a hex editor** (HxD, or `r2 -w`) | view/edit raw bytes of a file | verifying and applying the 6-byte patch |
| **PowerShell / bash** | scripting | automating scan/patch/backup/restore and the test matrix |

You don't need all of them. A realistic starting stack for a beginner: **Ghidra** (free, GUI, excellent docs) + **Process Monitor** + **a hex editor**.

---

## Part 4 — The method, as a repeatable recipe

This is the general pattern behind doc 02. You can apply it to almost any "why does this software check that, and what's the smallest safe change?" question.

1. **Inventory.** What files make up the product? What does it create on disk when you run it? (procmon + a file watch.)
2. **Read the readable parts first.** Web/Electron/JS components, config files, logs, string tables. You'll learn the system's vocabulary and find its data files.
3. **Form a hypothesis about the flow.** E.g. "the plugin reads a signed JSON file and only unlocks if signature + expiry pass."
4. **Build a test matrix.** Design small experiments where each row proves or kills one hypothesis (doc 02 Phase 2: original / forged / control). *This is the part most people skip — it's the part that makes everything else trustworthy.*
5. **Find the code via its data.** Search the binary for strings that appear in the data file (field names, endpoint names, keys). Follow cross-references from those strings to the function that uses them.
6. **Read that function.** Disassemble it; map each block to a behavior (status check, signature verify, time compare, return value).
7. **Choose the smallest robust change.** Prefer: one point, below all sub-checks, expressed as the function's own contract (its return value).
8. **Make it robust.** Locate the point by *content pattern* (unique bytes + a confirming nearby instruction), not by absolute offset. Fail safe on ambiguity.
9. **Make it reversible.** Backups + manifest + a restore path. Never write before the backup exists.
10. **Prove the matrix.** Fresh run, re-run (idempotent), reboot, restore, re-run. Screenshot/record evidence.

That recipe *is* the job. The specific bytes change every time; the recipe doesn't.

---

## Part 5 — Where this is appropriate (and where it isn't)

This work is defensible when **all** of these are true:

- you **own** the software (purchased, licensed to you)
- the vendor's service that performs the check is **gone** (defunct, shut down) and the product is unusable without it
- you're modifying **your own local copy** to restore a function you already paid for
- you're not redistributing the vendor's code/content, and not bypassing a *live, operating* license

It is **not** appropriate when the vendor is still operating and the license check is their current business model. The difference is not technical — it's the state of the other side. Keep that in mind when you take this skill anywhere else.

(There are also legal nuances around *decompilation* that vary by country; for restoration of your own purchased product with a dead vendor, the situation is generally more permissive than for reverse-engineering a live competitor, but you are responsible for your own context.)

---

## Part 6 — How to practice (legally)

- **Your own programs.** Write a small C/Python app with a fake "license check" and patch your own build. You'll learn hex, patterns, and the full recipe with zero risk.
- **CTFs and practice boxes.** Platforms like CrackMe collections (crackmes.one) exist specifically for practicing binary analysis on files made to be cracked.
- **Open-source decompilation.** Take an open-source program, compile it, then disassemble it and compare against the real source code. Nothing beats seeing "oh, *that* C function becomes *those* bytes."
- **Analyze your own machines.** Run procmon on apps you own and map what they read/write — safe, practical, and you'll start thinking in data flows.

A good first milestone: write a C program that checks a "key file" (hash it, compare), compile it, then find the comparison in the binary with Ghidra and patch it to always accept — the exact shape of this project, at hobby scale.

---

## Part 7 — Glossary (quick reference)

| Term | One-line meaning |
|------|------------------|
| byte | a number 0–255; the atomic unit of a file |
| hex editor | a program that shows/edits raw file bytes |
| disassembler | bytes → instruction text |
| decompiler | bytes → approximate source code (pseudo-C) |
| register | the CPU's scratchpad (EAX, RCX, ...) |
| calling convention | the agreement on how arguments/results are passed (x64 Windows: 1st arg RCX, result RAX) |
| function | a named chunk of code; has an entry, does a job, returns |
| cross-reference (xref) | "code at address A refers to data/string at address B" — your navigation links |
| prologue | the first few instructions of a function (save registers, set up stack) |
| pattern scan | finding code by its unique bytes rather than its address |
| idempotent | doing it twice = doing it once (safe to re-run) |
| JWT | a self-contained signed token with an expiry the app checks locally |
| public/private key | verifier / signer pair; you can't forge with the public one |
| signature chain | signature on data → signature on signer cert → root key in the app |
| Electron | a web app (HTML/JS/CSS) running in a Chromium shell; its code is in `app.asar` |
| app.asar | Electron's bundle archive; files keep their lengths recorded, enabling same-length in-place edits |
| gatekeeper | the single function that answers the key yes/no question everything depends on |
| patch | a few bytes changed in a binary to alter one behavior |

---

## Where to go next

- **Ghidra docs:** excellent for beginners, with tutorials.
- **x64dbg wiki:** for live debugging on Windows.
- **This repo's doc 02:** re-read it now that you know the vocabulary — every phase will make more sense.
- **Build your own CrackMe** (Part 6) — that's when it clicks.
