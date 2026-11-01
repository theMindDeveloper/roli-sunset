# ROLI Sunset Patcher v1.0
# Restores offline access to ROLI software after licensing servers shutdown.
# Patches the local entitlement check in installed ROLI products and installs
# a permanent offline entitlement file. Reversible: original files are backed up
# to %LOCALAPPDATA%\ROLI-Sunset\backup and can be restored with -Restore.
# Usage:  powershell -ExecutionPolicy Bypass -File ROLI-Sunset-Patcher.ps1 [-Restore] [-DryRun]
param([switch]$Restore,[switch]$DryRun)
$ErrorActionPreference='Stop'
$enc=[Text.Encoding]::GetEncoding(1252)
$BackupRoot=Join-Path $env:LOCALAPPDATA 'ROLI-Sunset\backup'
$Manifest=Join-Path $BackupRoot 'manifest.csv'
$SharedDir=Join-Path $env:APPDATA 'ROLI\Shared'
$PatternStr=$enc.GetString([byte[]]@(0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x55,0x57,0x41,0x54,0x41,0x56,0x41,0x57,0x48,0x8D,0xAC,0x24,0x30,0xFE,0xFF,0xFF,0x48,0x81,0xEC,0xD0,0x02,0x00,0x00))
$PatchBytes=[byte[]]@(0xB8,0x01,0x00,0x00,0x00,0xC3)
$GuardStr=$enc.GetString([byte[]]@(0x81,0x39,0xC8,0x00,0x00,0x00))
$AsarNeedles=@(
 @('clearCache(e){this.proxies.local.clearCrossAppCache(),this.proxies.local.cache.clear((e=>{if(e)throw e}))}','clearCache(e){}'),
 @('void this.unsetToken(e)','e(null,t,r)')
)

$EntB64='eyJoZWFkZXJzIjp7ImRhdGUiOiJUdWUsIDI3IE9jdCAyMDI2IDA1OjQ3OjMwIEdNVCIsImNvbnRlbnQtdHlwZSI6ImFwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLTgiLCJjb250ZW50LWxlbmd0aCI6IjM0MjgiLCJjb25uZWN0aW9uIjoiY2xvc2UiLCJzZXJ2ZXIiOiJuZ2lueCIsImFjY2Vzcy1jb250cm9sLWFsbG93LWNyZWRlbnRpYWxzIjoidHJ1ZSIsImFjY2Vzcy1jb250cm9sLWV4cG9zZS1oZWFkZXJzIjoiWC1BdXRoLVRva2VuLFgtUk9MSS1PVFAiLCJjb250ZW50LXNlY3VyaXR5LXBvbGljeSI6ImRlZmF1bHQtc3JjIFx1MDAyN3NlbGZcdTAwMjc7YmFzZS11cmkgXHUwMDI3c2VsZlx1MDAyNztibG9jay1hbGwtbWl4ZWQtY29udGVudDtmb250LXNyYyBcdTAwMjdzZWxmXHUwMDI3IGh0dHBzOiBkYXRhOjtmcmFtZS1hbmNlc3RvcnMgXHUwMDI3c2VsZlx1MDAyNztpbWctc3JjIFx1MDAyN3NlbGZcdTAwMjcgZGF0YTo7b2JqZWN0LXNyYyBcdTAwMjdub25lXHUwMDI3O3NjcmlwdC1zcmMgXHUwMDI3c2VsZlx1MDAyNztzY3JpcHQtc3JjLWF0dHIgXHUwMDI3bm9uZVx1MDAyNztzdHlsZS1zcmMgXHUwMDI3c2VsZlx1MDAyNyBodHRwczogXHUwMDI3dW5zYWZlLWlubGluZVx1MDAyNzt1cGdyYWRlLWluc2VjdXJlLXJlcXVlc3RzIiwiZXhwZWN0LWN0IjoibWF4LWFnZT0wIiwieC1mcmFtZS1vcHRpb25zIjoiU0FNRU9SSUdJTiIsInN0cmljdC10cmFuc3BvcnQtc2VjdXJpdHkiOiJtYXgtYWdlPTE1NTUyMDAwOyBpbmNsdWRlU3ViRG9tYWlucyIsIngtY29udGVudC10eXBlLW9wdGlvbnMiOiJub3NuaWZmIiwieC1wZXJtaXR0ZWQtY3Jvc3MtZG9tYWluLXBvbGljaWVzIjoibm9uZSIsInJlZmVycmVyLXBvbGljeSI6Im5vLXJlZmVycmVyIiwic2V0LWNvb2tpZSI6WyJ0b2tlbj1leUpoYkdjaU9pSklVekkxTmlJc0luUjVjQ0k2SWtwWFZDSjkuZXlKbGJXRnBiQ0k2SW0xdllXeG9ZV3B3WTBCbmJXRnBiQzVqYjIwaUxDSjBjbUZqYTJsdVoxOXBaQ0k2SWpnNVlUSmtNakV5TFRVeE0yUXROREkyTnkxaVpXVmxMV0V5TTJRMk1XRmxPVGM1TlNJc0luVnpaWEp1WVcxbElqb2lRV3hvWVdvaUxDSnliMnhsY3lJNlcxMHNJbVpwY25OMFgyNWhiV1VpT2lKTmIyaGhiVzFoWkNJc0lteGhjM1JmYm1GdFpTSTZJa0ZzYUdGcUlFaDFjM05sYVc0aUxDSnBaQ0k2SWpZMk1ERmhaVFl4TURoak5HUmtNMll4TmpSaE1qQmtOQ0lzSW1saGRDSTZNVGM1TXpBNE1EQTFNQ3dpWlhod0lqb3hOemsxTmpjeU1EVXdmUS5tbVFLeFB4NzlnOFEtREdEMWpmYVExUUoyWVFFbEJnY0dWdkMxVFNDV3JJOyBEb21haW49LnJvbGkuY29tOyBQYXRoPS87IEV4cGlyZXM9VGh1LCAyNiBOb3YgMjAyNiAwNTo0NzozMCBHTVQ7IEh0dHBPbmx5OyBTZWN1cmUiXSwiY2FjaGUtY29udHJvbCI6Im5vLWNhY2hlIn0sImJvZHkiOnsidWlkIjoiMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwIiwiZXhwaXJhdGlvbiI6NDEwMjQ0NDgwMCwiZW50aXRsZW1lbnRzIjp7ImNvbS5yb2xpLnJvbGlkYXNoYm9hcmQiOnsiaWQiOiI1ODBmN2VjMmQxOWRmZmMxOWU1ZDFlMWYiLCJuYW1lIjoiUk9MSSBEYXNoYm9hcmQiLCJlbmFibGVkIjp0cnVlfSwiY29tLmZ4cGFuc2lvbi5zdHJvYmUyLnN0dWJsb2FkZXIiOnsiaWQiOiI1OWJiOGUyNTQxMmY5YWM4MWFhMGQzNjYiLCJuYW1lIjoiU3Ryb2JlMiIsImxpY2VuY2VzIjpbInN0cm9iZS1wbGF5ZXIiXSwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnN0dWRpb3BsYXllciI6eyJpZCI6IjViNjBiNzhhMTZmMmI0OTU3YzdhMzQ1ZiIsIm5hbWUiOiJST0xJIFN0dWRpbyBQbGF5ZXIiLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc3R1ZGlvcGxheWVyLmJldGEiOnsiaWQiOiI1YjYwYjc4YTE2ZjJiNDk1N2M3YTM0NWYiLCJuYW1lIjoiUk9MSSBTdHVkaW8gUGxheWVyIiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5meHBhbnNpb24uY3lwaGVyMi5zdHVibG9hZGVyIjp7ImlkIjoiNWJhY2RhYjhlYTMxN2M1ZjQxODM2NGZiIiwibmFtZSI6IkN5cGhlcjIiLCJsaWNlbmNlcyI6WyJjeXBoZXItcGxheWVyIl0sImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5zdHVkaW9kcnVtcyI6eyJpZCI6IjVkYjAyODdlZmIyMDE4Mzk0MjBhZTIxYSIsIm5hbWUiOiJST0xJIFN0dWRpbyBEcnVtcyIsImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5lcXVhdG9yMiI6eyJpZCI6IjVlNWU0NzRhNjViY2RhNDAxYWE5OGFjMyIsIm5hbWUiOiJFcXVhdG9yMiIsImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5zdHVkaW9idW5kbGUiOnsiaWQiOiI1ZTc0OTYyM2Q3ODIxZWJjMjg4NDk5YjEiLCJuYW1lIjoiUk9MSSBTdHVkaW8iLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5lcXVhdG9yMmZ1bmRhbWVudGFscyI6eyJpZCI6IjYwMTJkZTFjN2VkZWQwMjQ1OWE3OGY2MyIsIm5hbWUiOiJFcXVhdG9yMiBGdW5kYW1lbnRhbHMiLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5tb3Rpb253YXZlcyI6eyJpZCI6IjYwZjgxMzY1Mjk1NzhhYzgzOGRkMGU1MyIsIm5hbWUiOiJNb3Rpb24gV2F2ZXMiLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5ncmFudWxhcm1vdGlvbiI6eyJpZCI6IjYxOGJlNDIyMzE2MjU3YTczMzVhZmFlYyIsIm5hbWUiOiJHcmFudWxhciBNb3Rpb24iLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5jeXBoZXIyZnVuZGFtZW50YWxzIjp7ImlkIjoiNWQ0NDUzN2EzYjI5MWFlMTc3MTNjNDBiIiwibmFtZSI6IkN5cGhlcjIgRnVuZGFtZW50YWxzIiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnNvdW5kcGFja3MuZGVwc3Rlc3QiOnsiaWQiOiI1ZDMyNGM4YTlmMDA4NDgyNTYyNjZlMDIiLCJuYW1lIjoiRGVwcyBUZXN0IiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLmVxdWF0b3IyLmVxMmZhY3Rvcnljb250ZW50MyI6eyJpZCI6IjVmMTk1NzgzYzNkNTJlY2EwYzgxNzUzYyIsIm5hbWUiOiJFcXVhdG9yMiBMaWJyYXJ5IiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnNvdW5kcGFja3MueG1hczE3Ijp7ImlkIjoiNWEyYWIxNDRjNmZhZTU5MzAzM2ZmNzYxIiwibmFtZSI6IkV4cHJlc3MgeW91ciBFbGYiLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5mdW5kYW1lbnRhbHMiOnsiaWQiOiI1OTFkOGIzZTAzNmY2MWU0MmRiMzRlZGYiLCJuYW1lIjoiRnVuZGFtZW50YWxzIiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnNvdW5kcGFja3MucGhhcnJlbGxoYXBweSI6eyJpZCI6IjU5ZGY5YTM2NzI5M2ViMTkxYjNkNWFiYyIsIm5hbWUiOiJIYXBweSIsImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5zb3VuZHBhY2tzLm5lcmRsZW1vbiI6eyJpZCI6IjU5ZmIwNDM1ZmI2YzM1M2E1MWI3YTYzMCIsIm5hbWUiOiJMZW1vbiIsImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5wb2x5Ijp7ImlkIjoiNTgwZjdlYzJkMTlkZmZjMTllNWQxZTI3IiwibmFtZSI6IlBvbHlUaHJ1IChCZXRhKSIsImVuYWJsZWQiOnRydWV9LCJjb20ucm9saS5odWIiOnsiaWQiOiI1YjIyZWY2MjUxYmE3YTMyN2Q0MTFkZmUiLCJuYW1lIjoiUk9MSSBDb25uZWN0IiwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnBsYWNlaG9sZGVyLmVxdWF0b3IiOnsiaWQiOiI1OTQ5MzdlYWJkOGVlNzQ3MTM4NGZjNjgiLCJuYW1lIjoiUk9MSSBFcXVhdG9yIiwibGljZW5jZXMiOlsiZXF1YXRvci1wbGF5ZXIiXSwiZW5hYmxlZCI6dHJ1ZX0sImNvbS5yb2xpLnJvbGlibG9ja3NzZXJ2ZXIiOnsiaWQiOiI1YjYxYjk2ZDMwNDEzMjM2MmM3M2ZiY2YiLCJuYW1lIjoiUk9MSSBIYXJkd2FyZSBEcml2ZXIiLCJlbmFibGVkIjp0cnVlfSwiY29tLnJvbGkuc291bmRwYWNrcy5zdHJvYmUyZnVuZGFtZW50YWxzIjp7ImlkIjoiNWQ0ODA0NTRiYmE5ZjcxZDBmZmM5OWU2IiwibmFtZSI6IlN0cm9iZTIgRnVuZGFtZW50YWxzIiwiZW5hYmxlZCI6dHJ1ZX19fX0='
$UserB64='eyJoZWFkZXJzIjp7ImRhdGUiOiJUdWUsIDI3IE9jdCAyMDI2IDA1OjQ3OjI5IEdNVCIsImNvbnRlbnQtdHlwZSI6ImFwcGxpY2F0aW9uL2pzb247IGNoYXJzZXQ9dXRmLTgiLCJjb250ZW50LWxlbmd0aCI6IjI1NDYiLCJjb25uZWN0aW9uIjoiY2xvc2UiLCJzZXJ2ZXIiOiJuZ2lueCIsImFjY2Vzcy1jb250cm9sLWFsbG93LWNyZWRlbnRpYWxzIjoidHJ1ZSIsImFjY2Vzcy1jb250cm9sLWV4cG9zZS1oZWFkZXJzIjoiWC1BdXRoLVRva2VuLFgtUk9MSS1PVFAiLCJjb250ZW50LXNlY3VyaXR5LXBvbGljeSI6ImRlZmF1bHQtc3JjIFx1MDAyN3NlbGZcdTAwMjc7YmFzZS11cmkgXHUwMDI3c2VsZlx1MDAyNztibG9jay1hbGwtbWl4ZWQtY29udGVudDtmb250LXNyYyBcdTAwMjdzZWxmXHUwMDI3IGh0dHBzOiBkYXRhOjtmcmFtZS1hbmNlc3RvcnMgXHUwMDI3c2VsZlx1MDAyNztpbWctc3JjIFx1MDAyN3NlbGZcdTAwMjcgZGF0YTo7b2JqZWN0LXNyYyBcdTAwMjdub25lXHUwMDI3O3NjcmlwdC1zcmMgXHUwMDI3c2VsZlx1MDAyNztzY3JpcHQtc3JjLWF0dHIgXHUwMDI3bm9uZVx1MDAyNztzdHlsZS1zcmMgXHUwMDI3c2VsZlx1MDAyNyBodHRwczogXHUwMDI3dW5zYWZlLWlubGluZVx1MDAyNzt1cGdyYWRlLWluc2VjdXJlLXJlcXVlc3RzIiwiZXhwZWN0LWN0IjoibWF4LWFnZT0wIiwieC1mcmFtZS1vcHRpb25zIjoiU0FNRU9SSUdJTiIsInN0cmljdC10cmFuc3BvcnQtc2VjdXJpdHkiOiJtYXgtYWdlPTE1NTUyMDAwOyBpbmNsdWRlU3ViRG9tYWlucyIsIngtY29udGVudC10eXBlLW9wdGlvbnMiOiJub3NuaWZmIiwieC1wZXJtaXR0ZWQtY3Jvc3MtZG9tYWluLXBvbGljaWVzIjoibm9uZSIsInJlZmVycmVyLXBvbGljeSI6Im5vLXJlZmVycmVyIiwiY2FjaGUtY29udHJvbCI6Im5vLWNhY2hlIn0sImJvZHkiOnsidHJhY2tpbmdfaWQiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAiLCJ1c2VybmFtZSI6IlJPTEkiLCJsb2NhdGlvbiI6IiIsImFib3V0X21lIjoiIiwiYXZhdGFyX2lkIjpudWxsLCJzb2NpYWwiOnsiZmFjZWJvb2siOm51bGwsInNvdW5kY2xvdWQiOm51bGwsInR3aXR0ZXIiOm51bGx9LCJwYXJ0bmVyIjpudWxsLCJrbGF2aXlvIjp7ImFjY291bnQiOiJldSJ9LCJjcmVhdGVkX2F0IjoiMjAyNC0wMy0yNVQxNzowMzoyOS45MThaIiwic3Vic2NyaXB0aW9ucyI6W10sInRyaWFsX2FjY2Vzc2VzIjpbXSwiZm9sbG93ZXJzX2NvdW50IjowLCJmb2xsb3dpbmdfY291bnQiOjEsImxpa2VzX2NvdW50IjowLCJhdmF0YXJfdXJsIjoiaHR0cHM6Ly9yZXMuY2xvdWRpbmFyeS5jb20vcm9saS1hc3NldHMvaW1hZ2UvdXBsb2FkL2NfZmlsbCxkX2RlZmF1bHRfdXNlci5qcGcsZHByXzIuMCxoXzE1MCx3XzE1MC91bmRlZmluZWQucG5nIiwibm9pc2VfZm1fdXJsX3BhdGgiOiIvQWxoYWoiLCJpZCI6IjAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMCIsImdyYWRpZW50IjpbIiNGQjhBNEQiLCIjOTNFODVEIl0sImZpcnN0X25hbWUiOiJST0xJIiwibGFzdF9uYW1lIjoiVXNlciIsImVtYWlsIjoiIiwiZW1haWxfcHJlZmVyZW5jZXMiOnsiT1BUX09VVF9PRl9BTEwiOmZhbHNlLCJPUFRfT1VUX09GX05PSVNFX0ZNX0RJR0VTVCI6ZmFsc2UsIkFERF9UT19QTEFZTElTVCI6dHJ1ZSwiQUxTT19SRU1JWEVEX1BST0pFQ1QiOnRydWUsIkNPTU1FTlRfT05fUFJPSkVDVCI6dHJ1ZSwiQ1JFQVRFX1RPS0VOIjp0cnVlLCJGT0xMT1dfVVNFUiI6dHJ1ZSwiRk9SS19QUk9KRUNUIjp0cnVlLCJHVUFSRElBTl9OT1RJRklFRCI6dHJ1ZSwiTElLRV9QUk9KRUNUIjp0cnVlLCJMVU1JX0dVQVJESUFOX05PVElGSUVEIjp0cnVlLCJMVU1JX1NUUklQRV9FVkVOVCI6dHJ1ZSwiTUVOVElPTl9VU0VSIjp0cnVlLCJSRU1JWF9QUk9KRUNUIjp0cnVlfSwicHVzaF9ub3RpZmljYXRpb25fcHJlZmVyZW5jZXMiOnsiT1BUX09VVF9PRl9BTEwiOmZhbHNlLCJBRERfVE9fUExBWUxJU1QiOnRydWUsIkFMU09fUkVNSVhFRF9QUk9KRUNUIjp0cnVlLCJDT01NRU5UX09OX1BST0pFQ1QiOnRydWUsIkNSRUFURV9UT0tFTiI6dHJ1ZSwiRk9MTE9XX1VTRVIiOnRydWUsIkZPUktfUFJPSkVDVCI6dHJ1ZSwiR1VBUkRJQU5fTk9USUZJRUQiOnRydWUsIkxJS0VfUFJPSkVDVCI6dHJ1ZSwiTFVNSV9HVUFSRElBTl9OT1RJRklFRCI6dHJ1ZSwiTFVNSV9TVFJJUEVfRVZFTlQiOnRydWUsIk1FTlRJT05fVVNFUiI6dHJ1ZSwiUkVNSVhfUFJPSkVDVCI6dHJ1ZX0sImNvcHBhX3N0YXR1cyI6ZmFsc2UsInBlbmRpbmciOmZhbHNlLCJyZXZva2VkIjpmYWxzZSwicHVibGlzaGVkX3Byb2plY3RzIjpbXSwicHJvZHVjdHMiOlt7Im5hbWUiOiJBYmxldG9uIExpdmUgMTEgTGl0ZSIsIm1ldGFkYXRhIjp7ImludGVybmFsX2lkIjpudWxsLCJpbWFnZXMiOltdfSwiaWQiOiI2MzRkMjAxM2I1Yjc2NjBmOTE0YTQyYTIiLCJ0eXBlIjoiZXh0ZXJuYWwifSx7Im5hbWUiOiJST0xJIFN0dWRpbyIsInR5cGUiOiJidW5kbGUiLCJtZXRhZGF0YSI6eyJpbnRlcm5hbF9pZCI6bnVsbCwiaW1hZ2VzIjpbXX0sImlkIjoiNWU3NDk2MjNkNzgyMWViYzI4ODQ5OWIxIn0seyJuYW1lIjoiRXF1YXRvcjIiLCJ0eXBlIjoic29mdHdhcmUiLCJtZXRhZGF0YSI6eyJpbnRlcm5hbF9pZCI6bnVsbCwiaW1hZ2VzIjpbXX0sImlkIjoiNWU1ZTQ3NGE2NWJjZGE0MDFhYTk4YWMzIn0seyJuYW1lIjoiU2VhYm9hcmQgUklTRTIiLCJ0eXBlIjoiaGFyZHdhcmUiLCJtZXRhZGF0YSI6eyJpbnRlcm5hbF9pZCI6bnVsbCwiaW1hZ2VzIjpbXX0sImlkIjoiNjIwYTdmM2Q3ZDAzMTk4ZDJkMmNhYzBjIn1dLCJvdXRzdGFuZGluZ19zdXJ2ZXlzIjpbXX19'

function Ensure-Admin {
  $p=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
  if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $a="-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if($Restore){$a+=" -Restore"}
    if($DryRun){$a+=" -DryRun"}
    Start-Process powershell -Verb RunAs -ArgumentList $a
    exit
  }
}
function Backup-File([string]$path){
  $rel=$path -replace '[:\\]','_'
  $dst=Join-Path $BackupRoot $rel
  if(-not (Test-Path $BackupRoot)){New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null}
  Copy-Item -LiteralPath $path -Destination $dst -Force
  if(-not (Test-Path $Manifest)){"Type,Path,Backup" | Set-Content -LiteralPath $Manifest}
  "$($args[0]),`"$path`",`"$dst`"" | Add-Content -LiteralPath $Manifest
}
function Patch-Binary([string]$path){
  $bytes=[IO.File]::ReadAllBytes($path)
  $hay=$enc.GetString($bytes)
  $idx=0; $hits=@()
  while((($idx=$hay.IndexOf($PatternStr,$idx)) -ge 0)){
    $guardPos=$hay.IndexOf($GuardStr,$idx)
    if($guardPos -ge 0 -and ($guardPos-$idx) -lt 96){$hits+=$idx}
    $idx+=1
  }
  if($hits.Count -eq 0){
    if($hay.Contains($enc.GetString($PatchBytes)+$PatternStr.Substring(6))){return "already-patched"}
    return "no-target"
  }
  if($hits.Count -gt 1){return "ambiguous($($hits.Count))"}
  $off=$hits[0]
  if($bytes[$off] -eq 0xB8 -and $bytes[$off+5] -eq 0xC3){return "already-patched"}
  Write-Host "  patch @ 0x$($off.ToString('x'))"
  if(-not $DryRun){
    Backup-File $path "BIN"
    for($i=0;$i -lt 6;$i++){$bytes[$off+$i]=$PatchBytes[$i]}
    [IO.File]::WriteAllBytes($path,$bytes)
  }
  return "patched"
}
function Patch-Asar([string]$path){
  $bytes=[IO.File]::ReadAllBytes($path)
  $hay=$enc.GetString($bytes)
  $changed=$false
  foreach($n in $AsarNeedles){
    $needle=$n[0]; $repl=$n[1]
    $pad=$repl + (' ' * ($needle.Length-$repl.Length))
    $i=0; $count=0
    while((($i=$hay.IndexOf($needle,$i)) -ge 0)){$count+=1;$i+=1}
    if($count -eq 0){
      $i=0
      while((($i=$hay.IndexOf($pad,$i)) -ge 0)){$count+=1;$i+=1}
      if($count -gt 0){Write-Host "  asar: '$($needle.Substring(0,[Math]::Min(30,$needle.Length)))...' already patched"; continue}
      Write-Host "  asar: needle not found: $($needle.Substring(0,40))..."
      continue
    }
    Write-Host "  asar: patching $count occurrence(s) of '$($needle.Substring(0,[Math]::Min(40,$needle.Length)))...'"
    if(-not $DryRun){
      if(-not $changed){Backup-File $path "ASAR"; $changed=$true}
      $i=0
      while((($i=$hay.IndexOf($needle,$i)) -ge 0)){
        for($k=0;$k -lt $needle.Length;$k++){$bytes[$i+$k]=[byte]$pad[$k]}
        $i+=$needle.Length
      }
      $hay=$enc.GetString($bytes)
    }
  }
  if($changed -and -not $DryRun){[IO.File]::WriteAllBytes($path,$bytes)}
  return $(if($changed){"patched"}else{"no-change"})
}
function Install-CacheFiles {
  if(-not (Test-Path $SharedDir)){New-Item -ItemType Directory -Force -Path $SharedDir | Out-Null}
  $f1=Join-Path $SharedDir '%2Fapi%2Fv1%2Fuser%2F.json'
  $f2=Join-Path $SharedDir '%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json'
  foreach($p in @($f1,$f2)){ if((Test-Path $p) -and -not $DryRun){Backup-File $p "CACHE"} }
  if(-not $DryRun){
    [IO.File]::WriteAllBytes($f2,[Convert]::FromBase64String($EntB64))
    [IO.File]::WriteAllBytes($f1,[Convert]::FromBase64String($UserB64))
  }
  "cache installed"
}
function Restore-All {
  if(-not (Test-Path $Manifest)){Write-Host "no backups found"; return}
  Import-Csv -LiteralPath $Manifest | ForEach-Object {
    if(Test-Path $_.Backup){
      Write-Host "restore $($_.Path)"
      Copy-Item -LiteralPath $_.Backup -Destination $_.Path -Force
    }
  }
  Write-Host "restore complete"
}

Ensure-Admin
if($Restore){Restore-All; return}

$dirs=@(
 (Join-Path ${env:ProgramFiles} 'ROLI'),
 (Join-Path ${env:ProgramFiles} 'Common Files\VST3'),
 (Join-Path ${env:ProgramFiles} 'Common Files\Avid\Pro Tools'),
 (Join-Path ${env:ProgramFiles} 'Steinberg\VST2'),
 (Join-Path ${env:ProgramFiles} 'VstPlugins'),
 (Join-Path ${env:CommonProgramFiles(x86)} 'VST3'),
 (Join-Path ${env:CommonProgramFiles(x86)} 'Steinberg\VstPlugins'),
 (Join-Path $env:LOCALAPPDATA 'VST3')
) | Where-Object {$_ -and (Test-Path $_)}
$files=@()
foreach($d in $dirs){$files+=Get-ChildItem $d -Recurse -File -Include *.exe,*.dll,*.vst3 -EA SilentlyContinue}
Write-Host "scanning $($files.Count) binaries in: $($dirs -join '; ')"
foreach($f in $files){
  Write-Host "[$($f.FullName)]"
  try{
    $r=Patch-Binary $f.FullName
    Write-Host "  => $r"
  }catch{Write-Host "  => error: $_"}
}
$asar=Join-Path ${env:ProgramFiles} 'ROLI\ROLI Connect\resources\app.asar'
if(Test-Path $asar){Write-Host "[ROLI Connect app.asar]"; Patch-Asar $asar | ForEach-Object {Write-Host "  => $_"}}
Write-Host "[entitlement cache]"
Install-CacheFiles | ForEach-Object {Write-Host "  => $_"}
Write-Host ""
Write-Host "DONE. Backups in $BackupRoot  (restore: powershell -File `"$PSCommandPath`" -Restore)"
if($DryRun){Write-Host "(dry run - nothing was modified)"}
