#!/usr/bin/env python3
"""Render documentation screenshots of the Council Queue model-driven app from the
solution's OWN metadata (ALM unpack) + the repo's OWN sample records.

Zero third-party deps: stdlib XML/JSON parsing + headless Chromium for the PNG.
Every image carries an on-image provenance strip — these are metadata renders,
not live-tenant captures; docs/capture-runbook.md describes the 1:1 replacement.

Usage:
  python3 tools/docs-render/render_screens.py --repo <council-repo-root> --out docs/screenshots
Chromium is located via $DOCS_RENDER_CHROMIUM, then PATH (chromium / chromium-browser /
google-chrome), then the Playwright pod default /opt/pw-browsers/chromium.
"""
import argparse
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

SOLUTION = "_bmad-output/implementation-artifacts/alm/unpacked/CouncilOfMinionsMVP"
IMPL = "_bmad-output/implementation-artifacts"
PROVENANCE = ("Rendered from solution metadata (ALM export in this repo) — not a live"
              " capture. Replace with a live screenshot via docs/capture-runbook.md.")


def find_chromium():
    # headless_shell first: plain chromium's new-headless --screenshot reserves ~87px
    # of window chrome inside --window-size, padding the PNG; headless_shell captures
    # the full viewport exactly (probe: fixed bottom bar at rows 874-899 of 900).
    cand = [os.environ.get("DOCS_RENDER_CHROMIUM")]
    cand += sorted(Path("/opt/pw-browsers").glob("chromium_headless_shell-*/chrome-linux/headless_shell"))
    cand += [shutil.which(n) for n in ("chromium-headless-shell", "chromium",
                                       "chromium-browser", "google-chrome")]
    cand.append("/opt/pw-browsers/chromium")
    for c in cand:
        if c and Path(c).exists():
            return str(c)
    sys.exit("no chromium found: set DOCS_RENDER_CHROMIUM or install chromium")


def parse_sitemap(root: Path):
    """Nav model: [(group_title, [(entity_logical, subarea_id), ...]), ...]"""
    sm = next((root / SOLUTION / "AppModuleSiteMaps").glob("*/AppModuleSiteMap.xml"))
    tree = ET.parse(sm)
    app_name = tree.findtext(".//LocalizedNames/LocalizedName[@languagecode='1033']/../LocalizedName") or ""
    ln = tree.find(".//LocalizedNames/LocalizedName")
    app_name = ln.get("description") if ln is not None else "App"
    groups = []
    for g in tree.iter("Group"):
        title = g.find("Titles/Title")
        ents = [(sa.get("Entity"), sa.get("Id")) for sa in g.iter("SubArea")]
        groups.append((title.get("Title") if title is not None else g.get("Id"), ents))
    return app_name, groups


def entity_display_names(root: Path):
    """{logical: (singular, plural)} from each Entity.xml."""
    out = {}
    for exml in (root / SOLUTION / "Entities").glob("*/Entity.xml"):
        try:
            t = ET.parse(exml)
        except ET.ParseError:
            continue
        logical = exml.parent.name
        singular = plural = None
        ln = t.find(".//EntityInfo/entity/LocalizedNames/LocalizedName[@languagecode='1033']")
        cn = t.find(".//EntityInfo/entity/LocalizedCollectionNames/LocalizedCollectionName[@languagecode='1033']")
        if ln is not None:
            singular = ln.get("description")
        if cn is not None:
            plural = cn.get("description")
        out[logical] = (singular or logical, plural or singular or logical)
    return out


def attribute_labels(root: Path, entity: str):
    """{logicalname: display label} for one entity."""
    exml = root / SOLUTION / "Entities" / entity / "Entity.xml"
    labels = {"createdon": "Created On"}
    if not exml.exists():
        return labels
    for attr in ET.parse(exml).iter("attribute"):
        logical = attr.findtext("LogicalName") or attr.get("PhysicalName", "")
        dn = attr.find("displaynames/displayname[@languagecode='1033']")
        if logical and dn is not None:
            labels[logical.lower()] = dn.get("description")
    return labels


def saved_views(root: Path, entity: str):
    """[(view_name, [column_logical,...])] skipping lookup/advanced-find plumbing views."""
    out = []
    qdir = root / SOLUTION / "Entities" / entity / "SavedQueries"
    if not qdir.exists():
        return out
    for q in sorted(qdir.glob("*.xml")):
        t = ET.parse(q)
        ln = t.find(".//LocalizedNames/LocalizedName")
        name = ln.get("description") if ln is not None else q.stem
        if any(s in name for s in ("Lookup View", "Advanced Find", "Quick Find",
                                   "Associated View")):
            continue
        cols = [c.get("name") for c in t.iter("cell")]
        if cols:
            out.append((name, cols))
    return out


def sample_records(root: Path):
    """{entity_logical: [record dicts]} from every *-slice.json sampleRecords block."""
    out = {}
    for p in sorted((root / IMPL).glob("*slice*.json")):
        try:
            d = json.loads(p.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for block in d.values():
            if isinstance(block, dict) and "sampleRecords" in block:
                ent = block.get("dataverseTable")
                if ent:
                    out.setdefault(ent, []).extend(block["sampleRecords"])
    return out


CSS = """
* { box-sizing:border-box; margin:0; }
body { font:14px 'Segoe UI',system-ui,sans-serif; color:#242424; background:#f0f0f0;
  display:flex; flex-direction:column; height:100vh; }
.top { height:48px; background:#0b4d8c; color:#fff; display:flex; align-items:center;
  padding:0 16px; gap:16px; }
.waffle { font-size:18px; letter-spacing:2px; }
.appname { font-weight:600; font-size:15px; }
.topright { margin-left:auto; display:flex; gap:14px; opacity:.9; font-size:13px; }
.frame { display:flex; flex:1; min-height:0; }
.nav { width:210px; background:#fff; border-right:1px solid #e0e0e0; overflow-y:auto;
  padding:6px 0; flex:none; }
.nav .sys { padding:7px 16px; color:#424242; font-size:13.5px; }
.nav h3 { font-size:11.5px; text-transform:uppercase; color:#616161; letter-spacing:.4px;
  padding:12px 16px 4px; font-weight:600; }
.nav a { display:block; padding:7px 16px 7px 22px; color:#242424; text-decoration:none;
  font-size:13.5px; border-left:3px solid transparent; }
.nav a.sel { background:#eff6fc; border-left-color:#0b4d8c; font-weight:600; }
.main { flex:1; display:flex; flex-direction:column; min-width:0; }
.cmdbar { background:#fff; border-bottom:1px solid #e0e0e0; padding:6px 14px; display:flex;
  gap:4px; align-items:center; }
.cmd { padding:6px 10px; font-size:13px; color:#242424; border-radius:3px; }
.cmd b { color:#0b4d8c; font-weight:400; margin-right:6px; }
.viewbar { background:#fff; padding:10px 16px 8px; display:flex; align-items:center; gap:8px; }
.viewname { font-size:17px; font-weight:600; }
.chev { color:#616161; font-size:11px; }
.grid { flex:1; background:#fff; margin:0 14px 12px; border:1px solid #e0e0e0;
  overflow:auto; }
table { border-collapse:collapse; width:100%; font-size:13px; }
th { text-align:left; font-weight:600; color:#424242; border-bottom:1px solid #e0e0e0;
  padding:9px 12px; white-space:nowrap; background:#fafafa; }
td { border-bottom:1px solid #f0f0f0; padding:9px 12px; white-space:nowrap;
  overflow:hidden; text-overflow:ellipsis; max-width:340px; }
tr:hover td { background:#f5faff; }
td.chk, th.chk { width:34px; text-align:center; color:#9a9a9a; }
td.name { color:#0b4d8c; font-weight:600; }
.count { color:#616161; font-size:12.5px; padding:8px 16px; }
.prov { position:fixed; bottom:0; left:0; right:0; height:26px; background:#fff4ce;
  color:#5c4400; font-size:11.5px; display:flex; align-items:center; padding:0 12px;
  border-top:1px solid #e8d99a; }
.frame { height:calc(100vh - 74px); }
"""


def fmt(v):
    if isinstance(v, bool):
        return "Yes" if v else "No"
    return str(v) if v is not None else ""


def grid_screen(app, groups, disp, labels, sel_entity, view_name, cols, rows):
    nav = ['<div class="sys">🏠 Home</div><div class="sys">🕒 Recent</div>'
           '<div class="sys">📌 Pinned</div>']
    for gtitle, ents in groups:
        nav.append(f"<h3>{html.escape(gtitle)}</h3>")
        for ent, _ in ents:
            cls = ' class="sel"' if ent == sel_entity else ""
            nav.append(f'<a{cls} href="#">{html.escape(disp.get(ent, (ent, ent))[1])}</a>')
    heads = "".join(f"<th>{html.escape(labels.get(c.lower(), c))} ⇅</th>" for c in cols)
    body = []
    for r in rows:
        tds = []
        for i, c in enumerate(cols):
            v = html.escape(fmt(r.get(c, "")))
            tds.append(f'<td class="name">{v}</td>' if i == 0 else f"<td>{v}</td>")
        body.append(f'<tr><td class="chk">☐</td>{"".join(tds)}</tr>')
    plural = disp.get(sel_entity, (sel_entity, sel_entity))[1]
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<div class="top"><span class="waffle">⠿</span><span class="appname">{html.escape(app)}</span>
<div class="topright"><span>🔍</span><span>＋</span><span>⚙</span><span>?</span><span>👤 Doug</span></div></div>
<div class="frame">
<nav class="nav">{''.join(nav)}</nav>
<div class="main">
<div class="cmdbar"><span class="cmd"><b>＋</b>New</span><span class="cmd"><b>🗑</b>Delete</span>
<span class="cmd"><b>⟳</b>Refresh</span><span class="cmd"><b>⚡</b>Flow</span><span class="cmd">⋯</span></div>
<div class="viewbar"><span class="viewname">{html.escape(view_name)}</span><span class="chev">▼</span></div>
<div class="grid"><table><tr><th class="chk">☐</th>{heads}</tr>{''.join(body)}</table>
<div class="count">1 - {len(rows)} of {len(rows)} · {html.escape(plural)}</div></div>
</div></div>
<div class="prov">⚠ {html.escape(PROVENANCE)}</div>
</body></html>"""


def shoot(chromium, html_text, out_png, size="1440,900"):
    with tempfile.TemporaryDirectory() as td:
        page = Path(td) / "page.html"
        page.write_text(html_text, encoding="utf-8")
        subprocess.run(
            [chromium, "--headless", "--disable-gpu", "--no-sandbox",
             "--hide-scrollbars", f"--window-size={size}",
             f"--screenshot={out_png}", page.as_uri()],
            check=True, capture_output=True, timeout=120)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".", help="Council repo root")
    ap.add_argument("--out", default="docs/screenshots")
    ap.add_argument("--only", default=None, help="render a single screen id")
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    out = Path(args.out)
    if not out.is_absolute():
        out = root / out
    out.mkdir(parents=True, exist_ok=True)
    chromium = find_chromium()

    app, groups = parse_sitemap(root)
    disp = entity_display_names(root)
    samples = sample_records(root)

    # One grid screen per daily-loop entity: its most doc-relevant view.
    screens = [
        ("grid-source-records-new", "com_councilsourcerecord", "New Source Records"),
        ("grid-source-records-held", "com_councilsourcerecord", "Held Source Records"),
        ("grid-work-items", "com_councilworkitem", "Proposed Work Items"),
        ("grid-work-items-approval", "com_councilworkitem", "Needs Human Approval"),
        ("grid-receipts", "com_councilreceipt", "Recent Receipts"),
        ("grid-briefs", "com_councilbrief", "Active Council Briefs"),
    ]
    made = []
    for sid, ent, want in screens:
        if args.only and sid != args.only:
            continue
        views = saved_views(root, ent)
        if not views:
            print(f"skip {sid}: no views for {ent}")
            continue
        name, cols = next(((n, c) for n, c in views if n == want), views[0])
        labels = attribute_labels(root, ent)
        rows = samples.get(ent, [])[:8]
        if not rows:  # deterministic placeholder rows, clearly demo-labeled
            rows = [{cols[0]: f"(demo) {disp.get(ent,(ent,ent))[0]} {i+1}"} for i in range(3)]
        png = out / f"{sid}.png"
        shoot(chromium, grid_screen(app, groups, disp, labels, ent, name, cols, rows), str(png))
        made.append(png)
        print(f"rendered {png.relative_to(root) if png.is_relative_to(root) else png}")
    print(f"{len(made)} screen(s) rendered by metadata; provenance strip on every image")


if __name__ == "__main__":
    main()
