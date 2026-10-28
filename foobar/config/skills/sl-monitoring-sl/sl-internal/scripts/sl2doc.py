#!/usr/bin/env python3
"""sl2doc.py — emit the sl-builder §10 companion doc for an SL-1.0 loop.

    python3 sl2doc.py <loop>.sl.json [-o docs/<id>.md] [--img-dir img]

Reads the coordinator-owned *.sl.json and writes a docs/<id>.md with the three
§10 sections: (1) what it is (rationale + dominant coherent-and-wrong, from the
`description`); (2) the loop at a glance (embeds img/<id>.svg, PNG fallback);
(3) disjointness at a glance (rationale, load-bearing barrier, the actors' (U,L)
table, the catchability table, the terminus) — all from the registry, so the doc
cannot drift from the .sl.json. Pair with sl2plantuml.py (which renders the SVG/PNG).
"""
import json, sys, argparse


def cell(x):
    """Flatten to a single safe Markdown-table cell."""
    if x is None:
        return "—"
    if isinstance(x, (list, tuple)):
        x = ", ".join(str(i) for i in x) if x else "—"
    return " ".join(str(x).split()).replace("|", "\\|") or "—"


def bound(b):
    if not b:
        return "—"
    t = cell(b.get("text") or ", ".join(b.get("sources", [])) or "—")
    tags = []
    if b.get("executable"):
        tags.append("⚙ executable")
    if b.get("borrowed_from"):
        tags.append(f"↩ borrowed from `{b['borrowed_from']}`")
    if b.get("absent_reason"):
        tags.append("∅ no executable oracle (terminus)")
    return t + (f" <br><sub>{' · '.join(tags)}</sub>" if tags else "")


def main():
    ap = argparse.ArgumentParser(description="Emit the §10 companion doc for an SL-1.0 loop.")
    ap.add_argument("json_file")
    ap.add_argument("-o", "--output", help="output .md path (default: docs/<id>.md)")
    ap.add_argument("--img-dir", default="img", help="image dir relative to the doc (default: img)")
    a = ap.parse_args()

    d = json.load(open(a.json_file))
    sid = d["id"]
    out = a.output or f"docs/{sid}.md"
    img = a.img_dir.rstrip("/")
    dj = d.get("disjointness", {}) or {}
    mon = d.get("monitors")
    mon_s = f"`{mon}`" if mon else "— (generic pattern, no fixed base)"

    L = []
    L.append(f"# {sid}\n")
    L.append(f"> **Kind** `{d.get('kind','—')}` · **Terrain** "
             f"{', '.join(d.get('terrain', [])) or '—'} · **Monitors** {mon_s}  ")
    L.append(f"> *SL-1.0 self-description:* `config/skills/{sid}/…` "
             f"(`{sid}.sl.json`)\n")

    L.append("## 1. What it is\n")
    L.append(d.get("description", "_(no description in registry)_").strip() + "\n")

    L.append("## 2. The loop at a glance\n")
    L.append(f"![{sid} squeeze loop]({img}/{sid}.svg)\n")
    L.append(f"<sub>PNG fallback: [`{img}/{sid}.png`]({img}/{sid}.png) · "
             f"regenerate with `sl2plantuml.py {sid}.sl.json --svg -o docs/{img}/{sid}.svg`</sub>\n")

    L.append("## 3. Disjointness at a glance\n")
    if dj.get("rationale"):
        L.append(dj["rationale"].strip() + "\n")
    if dj.get("load_bearing_barrier"):
        L.append(f"**Load-bearing barrier.** {dj['load_bearing_barrier'].strip()}\n")

    L.append("### Actors and their (U, L) pairs\n")
    L.append("| Actor (role) | Builds | Upper bound `U` | Lower bound `L` | Must not see |")
    L.append("|---|---|---|---|---|")
    for ac in d.get("actors", []):
        nm = f"**{cell(ac.get('name', ac['id']))}** <br>`{ac.get('role','')}`"
        L.append(f"| {nm} | {cell(ac.get('builds'))} | {bound(ac.get('upper_bound'))} "
                 f"| {bound(ac.get('lower_bound'))} | {cell(ac.get('must_not_see'))} |")
    L.append("")

    cat = dj.get("catchability") or []
    if cat:
        L.append("### Catchability — every characteristic blind spot is caught by *another* actor\n")
        L.append("| Actor | Characteristic blind spot | Caught by | Via |")
        L.append("|---|---|---|---|")
        for c in cat:
            L.append(f"| `{cell(c.get('actor'))}` | {cell(c.get('blind_spot'))} "
                     f"| **`{cell(c.get('caught_by'))}`** | {cell(c.get('via'))} |")
        L.append("")

    if dj.get("terminus"):
        L.append(f"**Terminus.** {dj['terminus'].strip()}\n")

    if dj.get("endogeneity_flags"):
        L.append(f"<sub>Endogeneity flags: {cell(dj['endogeneity_flags'])}</sub>\n")

    L.append("---\n")
    L.append(f"<sub>Generated from `{sid}.sl.json` by `sl2doc.py`; the registry is the source of "
             f"truth — edit the `.sl.json` and regenerate, do not hand-edit this file.</sub>\n")

    open(out, "w").write("\n".join(L))
    print(f"wrote doc → {out}")


if __name__ == "__main__":
    main()
