# 04 — The Offline Content Archive (Sounds & Instruments)

*The patcher restores **access**. This document covers restoring **content** — the actual sound-packs and instrument data. Together: patcher + offline license file + content archive = a fully server-free ROLI suite.*

---

## Why this exists

Even with the license patch, an app can only play sounds whose **audio data** exists on disk. ROLI delivered that data as `.rpkg` files (ROLI packages), downloaded on demand by ROLI Connect into:

```
%APPDATA%\ROLI\ROLI Connect\downloads\<hash-folder>\<name>.rpkg
```

When the servers died, no new `.rpkg` files can be fetched. Any that were **never downloaded** are gone — no patch can recreate data that doesn't exist on the machine. Any that **were** downloaded are yours, on disk, forever — this archive is their backup.

## What's in the archive

Created: 2026-11-01 · Size: **9.6 GB** · Format: `tar` (no compression — the audio is already compressed)

| File | What it is | Size |
|------|-----------|------|
| `equator2-2.5.2.rpkg` | Equator2 app + bundled content | 269 MB |
| `studioplayer-1.4.1.rpkg` | ROLI Studio Player app + bundled content | 229 MB |
| `studiodrums-1.4.1.rpkg` | ROLI Studio Drums app + bundled content | 81 MB |
| `Equator2 Factory Content-1.0.0.rpkg` | "Equator2 Library" sound pack | 5.0 GB |
| `equator2fundamentals-1.0.0.rpkg` | "Equator2 Fundamentals" sound pack | 2.6 GB |
| `Equator Legacy Content-1.1.0.rpkg` | Legacy Equator sound content | 1.3 GB |
| `motionwaves-1.0.0.rpkg` | "Motion Waves" sound pack | 7 MB |
| `granularmotion-1.0.0.rpkg` | "Granular Motion" sound pack | 6 MB |
| `DashboardInstallerWIN.exe` (+`.zip`) | ROLI Dashboard installer (stale leftover, kept for completeness) | ~40 MB |

The archive also preserves the `API Proxy Cache` (cached responses of `/api/v1/user/`, `/api/v1/user/entitlements/`, `/api/v1/user/products/`) so Connect's local state is complete.

**Integrity:** SHA256 of every file is in [`content/ROLI-SoundContent-2026-11-01.sha256`](../content/ROLI-SoundContent-2026-11-01.sha256). Verify after copy/transfer:

```powershell
# from the folder containing the .sha256 file, after extracting the tar:
cd $env:APPDATA\ROLI
Get-Content .\ROLI-SoundContent-2026-11-01.sha256 | ForEach-Object {
  $h, $path = $_ -split '  ', 2
  $actual = (Get-FileHash $path -Algorithm SHA256).Hash
  if ($actual -ne $h) { "MISMATCH: $path" }
}
"verify complete (no MISMATCH lines = all good)"
```

## Restoring the content

1. Put the extracted files back where they belong (the tar stores paths relative to `%APPDATA%\ROLI\`):

   ```powershell
   # on the machine with the archive, from %APPDATA%\ROLI:
   tar -xf C:\path\to\ROLI-SoundContent-2026-11-01.tar
   ```

   Or manually copy each `<hash-folder>` into `%APPDATA%\ROLI\ROLI Connect\downloads\`. The hash-folder names **matter** — don't rename them; the apps locate packages by those folders.

2. Make sure the offline license file is installed (the patcher does this):
   `%APPDATA%\ROLI\Shared\%2Fapi%2Fv1%2Fuser%2F.json` + `...entitlements.json`.

3. Launch the app. The sound packs appear in the library.

## What is NOT recoverable

These packs were **entitled** on the reference account but their `.rpkg` content was **never downloaded** to the machine — the audio only ever existed on ROLI's (now dead) store servers:

- Cypher2 Fundamentals
- Strobe2 Fundamentals
- Happy
- Lemon
- Express your Elf (xmas17)
- Fundamentals (generic)

No patch, file edit, or offline trick can restore data that was never on the disk. If a copy of these `.rpkg` files exists anywhere (another machine, an old backup), restore it the same way: into `%APPDATA%\ROLI\ROLI Connect\downloads\<any-folder>\`.

## How this fits the whole suite

| Piece | Restores | Provided by |
|-------|----------|-------------|
| Binary patches (6 exes/vst3s) | the signature/expiration *check* | the patcher |
| app.asar edits (2) | Connect's cache-wiping behavior | the patcher |
| Offline license file | the *exists* + *entitlement* checks | the patcher (embedded) |
| `.rpkg` content archive | the actual sounds/instruments | **this document's archive** |
| ROLI keyboard/hardware drivers | MIDI devices | installed separately, unaffected |

With all five in place, nothing in the suite needs a ROLI server: no login, no token, no store, no cloud sync. It runs on an airplane.
