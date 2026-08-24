import pathlib, re, sys

root = pathlib.Path(r"d:\zhanji\moshi_demo\assets")
skip = ("_legacy", "concept")
changed = 0
skipped = 0

for f in root.rglob("*.png.import"):
    parts = set(f.parts)
    if parts & set(skip):
        skipped += 1
        continue
    txt = f.read_text(encoding="utf-8")
    new = txt.replace("compress/mode=0", "compress/mode=1")
    new = new.replace("compress/lossy_quality=0.7", "compress/lossy_quality=0.8")
    if new != txt:
        f.write_text(new, encoding="utf-8")
        changed += 1

print(f"changed={changed} skipped={skipped}")
