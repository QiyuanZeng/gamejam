import sys, glob, os
from PIL import Image


def pack_bbox(pattern):
    files = sorted(glob.glob(pattern))
    if not files:
        return None
    box = None
    size = None
    for f in files:
        im = Image.open(f).convert("RGBA")
        size = im.size
        b = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
        if b is None:
            continue
        box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    return files[0], len(files), size, box


for pat in sys.argv[1:]:
    r = pack_bbox(pat)
    if r is None:
        print(pat, "NO FILES")
        continue
    first, n, size, box = r
    w, h = size
    bw, bh = box[2] - box[0], box[3] - box[1]
    cx = (box[0] + box[2]) / 2.0 / w
    cy = (box[1] + box[3]) / 2.0 / h
    print("%-70s n=%-3d canvas=%dx%d bbox=%s subj=%dx%d fill=%.3f center=(%.4f,%.4f) bottom=%.4f"
          % (pat, n, w, h, box, bw, bh, max(bw, bh) / float(max(w, h)), cx, cy, box[3] / float(h)))
