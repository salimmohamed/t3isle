#!/usr/bin/env python3
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

CANVAS_PX = 1024
BODY_PX = 824
MARGIN_PX = 100
BODY_CORNER_PX = 185.4
GRID = 128
UNIT_PX = BODY_PX / GRID

CAP_HEIGHT = 56
BAR = 12
STEM = 14
T_WIDTH = 48
LETTER_GAP = 4
THREE_WIDTH = 38
UPPER_BOWL = 10
LOWER_BOWL = 12
THREE_TOP_INSET = 4
THREE_SPUR = 7
CORNER = 1.5
LOCKUP_WIDTH = T_WIDTH + LETTER_GAP + THREE_WIDTH
LOCKUP_LEFT = (GRID - LOCKUP_WIDTH) / 2

EYE_WIDTH = 0.22
EYE_HEIGHT = 0.30
EYE_SPREAD = 0.30
GLINT = 0.26
GLINT_DX = 0.20
GLINT_DY = 0.28

SMALL_LOCKUP_SCALE = 1.18
SMALL_EYE_SCALE = 1.35

TILE_TOP = "#1C1C1F"
TILE_BOTTOM = "#050506"
LETTER_TOP = "#FFFFFF"
LETTER_BOTTOM = "#E6E8EF"
BLOB_LIGHT = "#FFC98F"
BLOB_BASE = "#FF9F43"
BLOB_DEEP = "#FF8A1F"
INK = "#121212"

BASELINE = 80
BLOB_COVERS_LETTERS_BY = 8
FACE_RADIUS = 44
EYE_Y = 98
BLOB = {"radius": 64, "lobes": 2, "wobble": 0.05, "phase": math.pi / 2,
        "ripples": 5, "ripple": 0.010, "ripple_phase": 1.2, "aspect": 1.07, "center_x": 66}


def n(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text == "-0" else text


def continuous_rect(x, y, w, h, r):
    k = [c * r for c in (1.528665, 1.08849296, 0.86840694, 0.63149379, 0.07491139, 0.37282383, 0.16905956)]
    a, b, c, d, e, f, g = k
    x2, y2 = x + w, y + h
    return "".join([
        f"M{n(x+a)},{n(y)}L{n(x2-a)},{n(y)}",
        f"C{n(x2-b)},{n(y)} {n(x2-c)},{n(y)} {n(x2-d)},{n(y+e)}",
        f"C{n(x2-f)},{n(y+g)} {n(x2-g)},{n(y+f)} {n(x2-e)},{n(y+d)}",
        f"C{n(x2)},{n(y+c)} {n(x2)},{n(y+b)} {n(x2)},{n(y+a)}L{n(x2)},{n(y2-a)}",
        f"C{n(x2)},{n(y2-b)} {n(x2)},{n(y2-c)} {n(x2-e)},{n(y2-d)}",
        f"C{n(x2-g)},{n(y2-f)} {n(x2-f)},{n(y2-g)} {n(x2-d)},{n(y2-e)}",
        f"C{n(x2-c)},{n(y2)} {n(x2-b)},{n(y2)} {n(x2-a)},{n(y2)}L{n(x+a)},{n(y2)}",
        f"C{n(x+b)},{n(y2)} {n(x+c)},{n(y2)} {n(x+d)},{n(y2-e)}",
        f"C{n(x+f)},{n(y2-g)} {n(x+g)},{n(y2-f)} {n(x+e)},{n(y2-d)}",
        f"C{n(x)},{n(y2-c)} {n(x)},{n(y2-b)} {n(x)},{n(y2-a)}L{n(x)},{n(y+a)}",
        f"C{n(x)},{n(y+b)} {n(x)},{n(y+c)} {n(x+e)},{n(y+d)}",
        f"C{n(x+g)},{n(y+f)} {n(x+f)},{n(y+g)} {n(x+d)},{n(y+e)}",
        f"C{n(x+c)},{n(y)} {n(x+b)},{n(y)} {n(x+a)},{n(y)}Z",
    ])


def rounded_rect(x, y, w, h, tl, tr, br, bl):
    x2, y2 = x + w, y + h
    d = f"M{n(x+tl)},{n(y)}L{n(x2-tr)},{n(y)}"
    d += f"A{n(tr)},{n(tr)} 0 0 1 {n(x2)},{n(y+tr)}" if tr else ""
    d += f"L{n(x2)},{n(y2-br)}"
    d += f"A{n(br)},{n(br)} 0 0 1 {n(x2-br)},{n(y2)}" if br else ""
    d += f"L{n(x+bl)},{n(y2)}"
    d += f"A{n(bl)},{n(bl)} 0 0 1 {n(x)},{n(y2-bl)}" if bl else ""
    d += f"L{n(x)},{n(y+tl)}"
    d += f"A{n(tl)},{n(tl)} 0 0 1 {n(x+tl)},{n(y)}" if tl else ""
    return d + "Z"


def half_ring(cx, cy, centerline, weight):
    outer, inner = centerline + weight / 2, centerline - weight / 2
    return (f"M{n(cx)},{n(cy-outer)}A{n(outer)},{n(outer)} 0 0 1 {n(cx)},{n(cy+outer)}"
            f"L{n(cx)},{n(cy+inner)}A{n(inner)},{n(inner)} 0 0 0 {n(cx)},{n(cy-inner)}Z")


def letter_t(x, y):
    stem_x = x + (T_WIDTH - STEM) / 2
    return (rounded_rect(x, y, T_WIDTH, BAR, CORNER, CORNER, CORNER, CORNER)
            + rounded_rect(stem_x, y + BAR - CORNER, STEM, CAP_HEIGHT - BAR + CORNER, 0, 0, CORNER, CORNER))


def letter_three(x, y):
    bowl_x = x + THREE_WIDTH - BAR / 2 - LOWER_BOWL
    upper_y = y + BAR / 2 + UPPER_BOWL
    waist_y = upper_y + UPPER_BOWL
    lower_y = waist_y + LOWER_BOWL
    top_bar = rounded_rect(x + THREE_TOP_INSET, y, bowl_x - x - THREE_TOP_INSET, BAR, CORNER, 0, 0, CORNER)
    spur = rounded_rect(bowl_x - THREE_SPUR, waist_y - BAR / 2, THREE_SPUR, BAR, CORNER, 0, 0, CORNER)
    bottom_bar = rounded_rect(x, y + CAP_HEIGHT - BAR, bowl_x - x, BAR, CORNER, 0, 0, CORNER)
    return (top_bar + half_ring(bowl_x, upper_y, UPPER_BOWL, BAR) + spur
            + half_ring(bowl_x, lower_y, LOWER_BOWL, BAR) + bottom_bar)


def lockup():
    top = BASELINE - CAP_HEIGHT
    return letter_t(LOCKUP_LEFT, top) + letter_three(LOCKUP_LEFT + T_WIDTH + LETTER_GAP, top)


def blob_points(cx, cy, radius, steps=96):
    points = []
    for i in range(steps):
        a = i / steps * 2 * math.pi
        k = (1 + BLOB["wobble"] * math.sin(BLOB["lobes"] * a + BLOB["phase"])
             + BLOB["ripple"] * math.sin(BLOB["ripples"] * a + BLOB["ripple_phase"]))
        points.append((cx + radius * k * math.cos(a) * BLOB["aspect"],
                       cy + radius * k * math.sin(a) / BLOB["aspect"]))
    return points


def smooth_closed(points):
    count = len(points)
    d = [f"M{n(points[0][0])},{n(points[0][1])}"]
    for i in range(count):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % count], points[(i + 2) % count]
        d.append(f"C{n(p1[0]+(p2[0]-p0[0])/6)},{n(p1[1]+(p2[1]-p0[1])/6)} "
                 f"{n(p2[0]-(p3[0]-p1[0])/6)},{n(p2[1]-(p3[1]-p1[1])/6)} {n(p2[0])},{n(p2[1])}")
    return "".join(d) + "Z"


def placed_blob():
    unit = blob_points(0, 0, BLOB["radius"])
    top_edge = BASELINE - BLOB_COVERS_LETTERS_BY
    cy = top_edge - min(p[1] for p in unit)
    return blob_points(BLOB["center_x"], cy, BLOB["radius"])


def eyes(cx, cy, radius, scale=1.0):
    w, h = radius * EYE_WIDTH * scale, radius * EYE_HEIGHT * scale
    spread = radius * EYE_SPREAD
    glint = radius * EYE_WIDTH * GLINT * scale
    shapes = []
    for side in (-1, 1):
        x = cx + side * spread
        shapes.append({"cx": x, "cy": cy, "rx": w / 2, "ry": h / 2,
                       "gx": x + w * GLINT_DX, "gy": cy - h / 2 + h * GLINT_DY, "gr": glint})
    return shapes


def eyes_svg(shapes, indent="    ", glints=True):
    lines = []
    for e in shapes:
        lines.append(f'{indent}<ellipse cx="{n(e["cx"])}" cy="{n(e["cy"])}" rx="{n(e["rx"])}" ry="{n(e["ry"])}" fill="{INK}"/>')
        if glints:
            lines.append(f'{indent}<circle cx="{n(e["gx"])}" cy="{n(e["gy"])}" r="{n(e["gr"])}" fill="#FFFFFF" fill-opacity="0.9"/>')
    return "\n".join(lines)


def blob_gradient(points):
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    left, right = max(min(xs), 0), min(max(xs), GRID)
    top, bottom = max(min(ys), 0), min(max(ys), GRID)
    return (f'<linearGradient id="blob" gradientUnits="userSpaceOnUse" '
            f'x1="{n(left+(right-left)*0.05)}" y1="{n(top)}" x2="{n(left+(right-left)*0.8)}" y2="{n(bottom)}">'
            f'<stop offset="0" stop-color="{BLOB_LIGHT}"/><stop offset="0.45" stop-color="{BLOB_BASE}"/>'
            f'<stop offset="1" stop-color="{BLOB_DEEP}"/></linearGradient>')


def icon_layers(blob, letters, small):
    face = eyes(BLOB["center_x"], EYE_Y, FACE_RADIUS, SMALL_EYE_SCALE if small else 1.0)
    grow = (f' transform="translate({GRID/2} {n(BASELINE)}) scale({SMALL_LOCKUP_SCALE}) translate({-GRID/2} {n(-BASELINE)})"'
            if small else "")
    layers = [f'    <path d="{letters}" fill="url(#letters)"{grow}/>']
    if not small:
        layers.append('    <g clip-path="url(#letters-clip)">')
        layers.append(f'      <path d="{blob}" transform="translate(0 -0.6)" fill="#000000" fill-opacity="0.42" filter="url(#cast)"/>')
        layers.append("    </g>")
    layers.append(f'    <path d="{blob}" fill="url(#blob)"/>')
    if not small:
        layers.append(f'    <path d="{blob}" fill="none" stroke="url(#rim)" stroke-width="2.4" clip-path="url(#blob-clip)"/>')
    layers.append(eyes_svg(face, glints=not small))
    return "\n".join("  " + line for line in "\n".join(layers).split("\n"))


def icon_svg(small=False):
    points = placed_blob()
    blob = smooth_closed(points)
    letters = lockup()
    body = continuous_rect(MARGIN_PX, MARGIN_PX, BODY_PX, BODY_PX, BODY_CORNER_PX)
    rim_top = min(p[1] for p in points)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS_PX}" height="{CANVAS_PX}" viewBox="0 0 {CANVAS_PX} {CANVAS_PX}">
  <title>T3 Isle app icon{" (16 and 32 px master)" if small else ""}</title>
  <defs>
    <linearGradient id="tile" gradientUnits="userSpaceOnUse" x1="0" y1="{MARGIN_PX}" x2="0" y2="{MARGIN_PX+BODY_PX}">
      <stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="edge" gradientUnits="userSpaceOnUse" x1="0" y1="{MARGIN_PX}" x2="0" y2="{MARGIN_PX+BODY_PX}">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0.04"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0.02"/>
    </linearGradient>
    <linearGradient id="letters" gradientUnits="userSpaceOnUse" x1="0" y1="{n(BASELINE-CAP_HEIGHT)}" x2="0" y2="{n(BASELINE)}">
      <stop offset="0" stop-color="{LETTER_TOP}"/><stop offset="1" stop-color="{LETTER_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="rim" gradientUnits="userSpaceOnUse" x1="0" y1="{n(rim_top)}" x2="0" y2="{n(rim_top + 14)}">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    {blob_gradient(points)}
    <filter id="drop" filterUnits="userSpaceOnUse" x="0" y="0" width="{CANVAS_PX}" height="{CANVAS_PX}"><feGaussianBlur stdDeviation="11"/></filter>
    <filter id="cast" filterUnits="userSpaceOnUse" x="-16" y="-16" width="{GRID+32}" height="{GRID+32}"><feGaussianBlur stdDeviation="1.1"/></filter>
    <clipPath id="body"><path d="{body}"/></clipPath>
    <clipPath id="letters-clip"><path d="{letters}"/></clipPath>
    <clipPath id="blob-clip"><path d="{blob}"/></clipPath>
  </defs>
  <path d="{body}" transform="translate(0 12)" fill="#000000" fill-opacity="0.32" filter="url(#drop)"/>
  <path d="{body}" fill="url(#tile)"/>
  <g clip-path="url(#body)">
    <g transform="translate({MARGIN_PX} {MARGIN_PX}) scale({UNIT_PX})">
{icon_layers(blob, letters, small)}
    </g>
  </g>
  <path d="{body}" fill="none" stroke="url(#edge)" stroke-width="3" clip-path="url(#body)"/>
</svg>
"""


def layer_svg(content, defs=""):
    return (f'<svg width="{GRID}" height="{GRID}" viewBox="0 0 {GRID} {GRID}" fill="none" xmlns="http://www.w3.org/2000/svg">\n'
            f'{defs}{content}\n</svg>\n')


def icon_composer_group(name, image):
    return {
        "layers": [{"image-name": image, "name": name,
                    "position": {"scale": CANVAS_PX / GRID, "translation-in-points": [0, 0]}}],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": False, "value": 0.5},
    }


def icon_composer_project():
    points = placed_blob()
    face = eyes(BLOB["center_x"], EYE_Y, FACE_RADIUS)
    defs = f"  <defs>{blob_gradient(points)}</defs>\n"
    blob_layer = layer_svg(f'  <path d="{smooth_closed(points)}" fill="url(#blob)"/>\n{eyes_svg(face, "  ")}', defs)
    text_layer = layer_svg(f'  <path d="{lockup()}" fill="white"/>')
    manifest = {
        "fill": {"solid": "display-p3:0.05500,0.05500,0.06300,1.00000"},
        "groups": [icon_composer_group("Blob", "blob.svg"), icon_composer_group("Text", "text.svg")],
        "supported-platforms": {"squares": ["macOS"]},
    }
    return manifest, {"blob.svg": blob_layer, "text.svg": text_layer}


def blob_dome(radius, steps=240):
    dense = blob_points(0, 0, radius, steps)
    cut = 0.18 * radius
    kept = [p for p in dense if p[1] <= cut]
    seam = max(range(len(kept)), key=lambda i: math.hypot(kept[i][0] - kept[i - 1][0], kept[i][1] - kept[i - 1][1]))
    return kept[seam:] + kept[:seam]


def menubar_svg():
    size, live = 18, 16
    radius = live / 2 / (BLOB["aspect"] * (1 + BLOB["wobble"]))
    arc = blob_dome(radius)
    ys = [p[1] for p in arc]
    dx, dy = size / 2, size / 2 - (min(ys) + max(ys)) / 2
    outline = "M" + "L".join(f"{n(x+dx)},{n(y+dy)}" for x, y in arc) + "Z"
    eye_y = (min(ys) + max(ys)) / 2 + dy + 0.4
    holes = ""
    for e in eyes(dx, eye_y, radius * 1.05, scale=1.25):
        holes += (f'M{n(e["cx"]-e["rx"])},{n(e["cy"])}a{n(e["rx"])},{n(e["ry"])} 0 1 0 {n(2*e["rx"])},0'
                  f'a{n(e["rx"])},{n(e["ry"])} 0 1 0 {n(-2*e["rx"])},0Z')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 {size} {size}">\n'
            f'  <title>T3 Isle menu bar glyph</title>\n'
            f'  <path d="{outline}{holes}" fill="#000000" fill-rule="evenodd"/>\n</svg>\n')


def social_svg():
    inner = icon_svg().split("\n", 2)[2].rsplit("</svg>", 1)[0]
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640">\n'
            f'  <title>T3 Isle social preview</title>\n'
            f'  <rect width="1280" height="640" fill="#0B0B0D"/>\n'
            f'  <svg x="400" y="80" width="480" height="480" viewBox="0 0 {CANVAS_PX} {CANVAS_PX}">\n{inner}  </svg>\n</svg>\n')


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        handle.write(text)


def main(out_dir):
    write(os.path.join(out_dir, "icon.svg"), icon_svg())
    write(os.path.join(out_dir, "icon-small.svg"), icon_svg(small=True))
    write(os.path.join(out_dir, "menubar.svg"), menubar_svg())
    write(os.path.join(out_dir, "social-preview.svg"), social_svg())
    manifest, layers = icon_composer_project()
    project = os.path.join(HERE, "AppIcon.icon")
    write(os.path.join(project, "icon.json"), json.dumps(manifest, indent=2) + "\n")
    for name, text in layers.items():
        write(os.path.join(project, "Assets", name), text)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
