from PIL import Image
from pathlib import Path

src = Path(r"C:\Users\Administrator\.cursor\projects\c-Users-Administrator-safesecurity\assets")
out_root = Path(r"C:\Users\Administrator\Downloads\SafeAlert-AppStore-Screenshots")
out_iphone = out_root / "iPhone-DynamicIsland-medium-1206x2622"
out_ipad = out_root / "iPad-13inch-2064x2752"
out_iphone.mkdir(parents=True, exist_ok=True)
out_ipad.mkdir(parents=True, exist_ok=True)


def fit_cover(img: Image.Image, tw: int, th: int) -> Image.Image:
    w, h = img.size
    target_ratio = tw / th
    ratio = w / h
    if ratio > target_ratio:
        nw = int(h * target_ratio)
        left = (w - nw) // 2
        img = img.crop((left, 0, left + nw, h))
    else:
        nh = int(w / target_ratio)
        top = (h - nh) // 2
        img = img.crop((0, top, w, top + nh))
    return img.resize((tw, th), Image.Resampling.LANCZOS)


iphone_files = [
    ("sa-iphone-home-v2.jpg", "01-home.png"),
    ("sa-iphone-sos-v2.jpg", "02-sos.png"),
    ("sa-iphone-map-v2.jpg", "03-map.png"),
]
ipad_files = [
    ("sa-ipad-home-v2.jpg", "01-home.png"),
    ("sa-ipad-sos-v2.jpg", "02-sos.png"),
    ("sa-ipad-map-v2.jpg", "03-map.png"),
]

for src_name, dest_name in iphone_files:
    im = Image.open(src / src_name).convert("RGB")
    out = fit_cover(im, 1206, 2622)
    dest = out_iphone / dest_name
    out.save(dest, "PNG", optimize=True)
    print(f"iphone {dest_name} {out.size} {dest.stat().st_size}")

for src_name, dest_name in ipad_files:
    im = Image.open(src / src_name).convert("RGB")
    out = fit_cover(im, 2064, 2752)
    dest = out_ipad / dest_name
    out.save(dest, "PNG", optimize=True)
    print(f"ipad {dest_name} {out.size} {dest.stat().st_size}")

print("DONE", out_root)
