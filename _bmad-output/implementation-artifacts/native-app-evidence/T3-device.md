# T3 evidence — device sign-in (story 6-2, in progress)

**2026-08-02 ~23:07 (device local), Doug's iPhone.** Screenshot:
`t3-iphone-powerapps-home.png`.

PROVEN on device:
- Signed in as Doug (profile + personal app list) — tenant identity works on
  the phone.
- **Correct environment visible:** "Council Queue — Doug Holbrook — Doug
  Holbrook's Environment" in Recent apps (sdhdev, the 6-2 target env).
- The EXISTING model-driven Council Queue app is reachable on the device —
  the current approve/decline surface works mobile today (fallback demo).

REMAINING for T3 green: the same sign-in inside the **Power Apps Developer**
app (separate install — App Store id 6753083462, the QR-scan native preview
runtime). Completes alongside T2/T4 in the Council-rooted scaffold session
(clearance brief: 6-2-clearance-brief.md).

Gate state: T1 ✅ · **T3 partial (identity+env proven; Developer app pending)**
· T2/T4 queued on the scaffold session.

## T3 GREEN — 2026-08-02 ~23:45 (device local)

Second screenshot `t3-iphone-preview-ready.png`: **Power Apps Mobile Preview**
(the QR-scan native runtime; App Store lists it under this name, docs call it
the Developer app) installed, authenticated, status **Ready** — "Launch a
native app session / Scan QR / Enter URL", no sessions yet. Combined with the
first screenshot (same device+account, sdhdev environment reachable), T3's
substance is proven: device, identity, runtime ready, environment access.
The environment name renders in-app at first session launch — captured as
part of T4's evidence when the scaffold's QR is scanned.

**Gate state: T1 ✅ · T3 ✅ · T2/T4 → the Council-rooted scaffold session.**
