#!/usr/bin/env python3
"""Populate specs/ with the FIPS 140-3 corpus listed in MANIFEST.tsv.

Usage: specs/import-specs.py [--with-restricted] [--checklist DIR] [SRC_DIR ...]
       specs/import-specs.py --status

Each PDF found under SRC_DIR whose sha256 is a MANIFEST.tsv row is copied to
specs/pdf/<id>.pdf and its text extracted to specs/text/<id>.txt (pdftotext,
reading order). A file with a manifest source_name but another digest is a
different edition: it is reported and not imported. Documents with license
"restricted" (ISO/IEC 19790, 24759) are imported only with
--with-restricted: their licence is per licensee and may forbid copying them
into shared or automated environments. Check it before passing the flag.

--checklist DIR copies a FIPS-Checklist (data/*.jsonl, build_checklist.py,
preamble.md) to specs/checklist/ and rebuilds its Markdown, CSV and index.

PDFs, text and checklist are never committed (specs/.gitignore).
"""

import argparse
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

SPECS = Path(__file__).resolve().parent


def load_manifest(path=SPECS / "MANIFEST.tsv"):
    rows, header = [], None
    for line in path.read_text().splitlines():
        if not line or line.startswith("#"):
            continue
        cells = line.split("\t")
        if header is None:
            header = cells
            continue
        rows.append(dict(zip(header, cells)))
    return rows


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def status(rows):
    missing = 0
    for r in rows:
        pdf = SPECS / "pdf" / f"{r['id']}.pdf"
        txt = SPECS / "text" / f"{r['id']}.txt"
        state = "present" if pdf.is_file() else "MISSING"
        missing += not pdf.is_file()
        extra = " +text" if txt.is_file() else ""
        print(f"{state:8} {r['id']:18} {r['status']:6} {r['license']:10} {r['source_name']}{extra}")
    chk = SPECS / "checklist" / "FIPS140-3_Checklist.md"
    print(f"checklist: {'present' if chk.is_file() else 'MISSING'}")
    print(f"{len(rows) - missing} of {len(rows)} documents present")
    return 0


def extract(pdf, txt):
    if shutil.which("pdftotext") is None:
        return False
    r = subprocess.run(["pdftotext", "-enc", "UTF-8", str(pdf), str(txt)],
                       capture_output=True, text=True)
    return r.returncode == 0


def import_checklist(src):
    src = Path(src)
    dest = SPECS / "checklist"
    if not (src / "data").is_dir() or not (src / "build_checklist.py").is_file():
        print(f"import-specs: {src} is not a FIPS-Checklist (no data/ or build_checklist.py)",
              file=sys.stderr)
        return 1
    (dest / "data").mkdir(parents=True, exist_ok=True)
    for f in sorted((src / "data").glob("*.jsonl")):
        shutil.copy2(f, dest / "data" / f.name)
    for name in ("build_checklist.py", "preamble.md"):
        if (src / name).is_file():
            shutil.copy2(src / name, dest / name)
    r = subprocess.run([sys.executable, str(dest / "build_checklist.py")], cwd=dest,
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout + r.stderr, file=sys.stderr)
        return 1
    print(f"checklist: imported {len(list((dest / 'data').glob('*.jsonl')))} chapter files "
          f"to {dest.relative_to(SPECS.parent)}")
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--with-restricted", action="store_true",
                   help="also import documents whose manifest license is 'restricted'")
    p.add_argument("--checklist", metavar="DIR", help="import a FIPS-Checklist directory")
    p.add_argument("--status", action="store_true", help="list present and missing documents")
    p.add_argument("sources", nargs="*", metavar="SRC_DIR")
    a = p.parse_args(argv)
    rows = load_manifest()
    if a.status:
        return status(rows)
    if not a.sources and not a.checklist:
        p.error("give at least one SRC_DIR, --checklist DIR or --status")
    by_hash = {r["sha256"]: r for r in rows}
    by_name = {r["source_name"]: r for r in rows}
    (SPECS / "pdf").mkdir(exist_ok=True)
    (SPECS / "text").mkdir(exist_ok=True)
    rc = 0
    for src in a.sources:
        for f in sorted(Path(src).rglob("*.pdf")):
            if SPECS in f.resolve().parents:
                continue
            digest = sha256(f)
            r = by_hash.get(digest)
            if r is None:
                if f.name in by_name:
                    print(f"edition  {f}: sha256 differs from MANIFEST.tsv row "
                          f"{by_name[f.name]['id']}; not imported")
                continue
            if r["license"] == "restricted" and not a.with_restricted:
                print(f"skipped  {r['id']:18} restricted licence (use --with-restricted)")
                continue
            pdf = SPECS / "pdf" / f"{r['id']}.pdf"
            shutil.copy2(f, pdf)
            txt = SPECS / "text" / f"{r['id']}.txt"
            ok = extract(pdf, txt)
            print(f"imported {r['id']:18} <- {f.name}{'' if ok else ' (no text: pdftotext failed)'}")
    if a.checklist:
        rc |= import_checklist(a.checklist)
    present = sum((SPECS / "pdf" / f"{r['id']}.pdf").is_file() for r in rows)
    print(f"{present} of {len(rows)} documents present")
    return rc


if __name__ == "__main__":
    sys.exit(main())
