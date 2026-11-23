"""Generate Phase 0 VRoid texture atlases from the base textures.

Run:
    blender --background --factory-startup --python scripts/generate_textures.py

The base VRoid atlas layout is kept unchanged; only colors/shading are
repainted. Outputs go to textures/phase0/.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "config" / "avatar.json").read_text(encoding="utf-8"))
BASE_DIR = ROOT / "work" / "base" / "textures"
OUT_DIR = ROOT / "textures" / "phase0"


def hex_rgb(value: str) -> np.ndarray:
    value = value.lstrip("#")
    return np.array([int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


PALETTE = {key: hex_rgb(value) for key, value in CONFIG["palette"].items()}


def load_image(name: str) -> np.ndarray:
    path = BASE_DIR / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"缺少底座贴图: {path}")
    image = bpy.data.images.load(str(path))
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    # Blender image rows are bottom-up; use top-down arrays for drawing.
    array = pixels.reshape(height, width, 4)[::-1].copy()
    bpy.data.images.remove(image)
    return array


def save_image(name: str, array: np.ndarray) -> Path:
    height, width = array.shape[:2]
    image = bpy.data.images.new(name=name, width=width, height=height, alpha=True, float_buffer=False)
    image.colorspace_settings.name = "sRGB"
    image.alpha_mode = "STRAIGHT"
    pixels = np.ascontiguousarray(array[::-1].reshape(-1).astype(np.float32))
    image.pixels.foreach_set(pixels)
    output = OUT_DIR / f"{name}.png"
    image.filepath_raw = str(output)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    return output


def luma(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def lerp(a: np.ndarray | float, b: np.ndarray | float, t: np.ndarray | float) -> np.ndarray:
    return a + (b - a) * t


def colorize(array: np.ndarray, color, power: float = 0.85, low: float = 0.5, high: float = 1.5) -> np.ndarray:
    """Preserve source shading while moving the average color to `color`."""
    rgb = array[..., :3]
    alpha = array[..., 3]
    mask = alpha > 0.01
    if not np.any(mask):
        return array
    brightness = luma(rgb)
    mean = float(brightness[mask].mean()) or 1.0
    factor = np.clip((brightness / mean) ** power, low, high)
    target = np.asarray(color, dtype=np.float32)
    out = array.copy()
    out[..., :3] = np.clip(target[None, None, :] * factor[..., None], 0.0, 1.0)
    return out


def colorize_gradient(array: np.ndarray, color_fn, power: float = 0.85, low: float = 0.5, high: float = 1.5) -> np.ndarray:
    rgb = array[..., :3]
    alpha = array[..., 3]
    mask = alpha > 0.01
    if not np.any(mask):
        return array
    brightness = luma(rgb)
    mean = float(brightness[mask].mean()) or 1.0
    factor = np.clip((brightness / mean) ** power, low, high)
    height, width = brightness.shape
    yy, xx = np.mgrid[0:height, 0:width]
    color = color_fn(yy / max(height - 1, 1), xx / max(width - 1, 1), brightness)
    out = array.copy()
    out[..., :3] = np.clip(color * factor[..., None], 0.0, 1.0)
    return out


def add_radial_blush(array: np.ndarray, cx: float, cy: float, rx: float, ry: float, color, strength: float = 0.5) -> None:
    height, width = array.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width]
    nx = (xx / max(width - 1, 1) - cx) / rx
    ny = (yy / max(height - 1, 1) - cy) / ry
    dist = np.sqrt(nx * nx + ny * ny)
    falloff = np.clip(1.0 - dist, 0.0, 1.0) ** 2
    alpha = falloff * strength
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - alpha[..., None]) + target[None, None, :] * alpha[..., None]


def draw_soft_disc(array: np.ndarray, cx: float, cy: float, radius: float, color, strength: float = 1.0) -> None:
    height, width = array.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width]
    nx = xx / max(width - 1, 1) - cx
    ny = yy / max(height - 1, 1) - cy
    dist = np.sqrt(nx * nx + ny * ny)
    falloff = np.clip(1.0 - dist / radius, 0.0, 1.0) ** 1.5 * strength
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - falloff[..., None]) + target[None, None, :] * falloff[..., None]


def draw_ellipse(array: np.ndarray, cx: float, cy: float, rx: float, ry: float, color, feather: float = 0.08, strength: float = 1.0) -> None:
    height, width = array.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width]
    nx = (xx - cx * width) / max(rx * width, 1e-6)
    ny = (yy - cy * height) / max(ry * height, 1e-6)
    dist = np.sqrt(nx * nx + ny * ny)
    mask = np.clip((1.0 - dist) / max(feather, 1e-4), 0.0, 1.0) * strength
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - mask[..., None]) + target[None, None, :] * mask[..., None]


def draw_ellipse_arc(array: np.ndarray, cx: float, cy: float, rx: float, ry: float, width: float, color, upper: bool = True, strength: float = 1.0) -> None:
    height, width_px = array.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width_px]
    nx = (xx - cx * width_px) / max(rx * width_px, 1e-6)
    ny = (yy - cy * height) / max(ry * height, 1e-6)
    dist = np.sqrt(nx * nx + ny * ny)
    mask = np.exp(-((dist - 1.0) / max(width, 1e-4)) ** 2) * strength
    mask *= (yy < cy * height) if upper else (yy > cy * height)
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - mask[..., None]) + target[None, None, :] * mask[..., None]


def draw_ellipse_ring(array: np.ndarray, cx: float, cy: float, rx: float, ry: float, width: float, color, strength: float = 1.0) -> None:
    height, width_px = array.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width_px]
    nx = (xx - cx * width_px) / max(rx * width_px, 1e-6)
    ny = (yy - cy * height) / max(ry * height, 1e-6)
    dist = np.sqrt(nx * nx + ny * ny)
    mask = np.exp(-((dist - 1.0) / max(width, 1e-4)) ** 2) * strength
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - mask[..., None]) + target[None, None, :] * mask[..., None]


def lighten_hair_root(array: np.ndarray, threshold: float = 0.60, strength: float = 0.90) -> np.ndarray:
    """Lift the crown/root of the hair texture toward the silver root color."""
    height = array.shape[0]
    v = 1.0 - np.arange(height, dtype=np.float32) / max(height - 1, 1)
    weight = np.clip((v - threshold) / (1.0 - threshold), 0.0, 1.0) ** 0.7 * strength
    target = PALETTE["hairRoot"]
    array[..., :3] = array[..., :3] * (1.0 - weight[:, None, None]) + target[None, None, :] * weight[:, None, None]
    return array


def fill_transparent(array: np.ndarray, color) -> np.ndarray:
    """Fill transparent atlas background for opaque VRoid materials.

    The USD exporter connects texture alpha to UsdPreviewSurface opacity even
    for Alpha Mode = opaque; transparent atlas backgrounds then show the black
    body underneath. Filling the background keeps Blender and USD consistent.
    """
    mask = array[..., 3] < 0.99
    target = np.asarray(color, dtype=np.float32)
    array[..., :3][mask] = target
    array[..., 3][mask] = 1.0
    return array


def draw_polyline(array: np.ndarray, points: list[tuple[float, float]], color, width: float = 3.0, feather: float = 1.5) -> None:
    height, width_px = array.shape[:2]
    mask = np.zeros((height, width_px), dtype=np.float32)
    for (x0, y0), (x1, y1) in zip(points[:-1], points[1:]):
        px0, py0 = x0 * (width_px - 1), y0 * (height - 1)
        px1, py1 = x1 * (width_px - 1), y1 * (height - 1)
        min_x = max(0, int(min(px0, px1) - width - feather - 2))
        max_x = min(width_px, int(max(px0, px1) + width + feather + 2))
        min_y = max(0, int(min(py0, py1) - width - feather - 2))
        max_y = min(height, int(max(py0, py1) + width + feather + 2))
        if max_x <= min_x or max_y <= min_y:
            continue
        yy, xx = np.mgrid[min_y:max_y, min_x:max_x]
        dx, dy = px1 - px0, py1 - py0
        length_sq = dx * dx + dy * dy
        if length_sq <= 1e-9:
            distance = np.sqrt((xx - px0) ** 2 + (yy - py0) ** 2)
        else:
            t = np.clip(((xx - px0) * dx + (yy - py0) * dy) / length_sq, 0.0, 1.0)
            distance = np.sqrt((xx - (px0 + t * dx)) ** 2 + (yy - (py0 + t * dy)) ** 2)
        influence = np.clip((width * 0.5 + feather - distance) / feather, 0.0, 1.0)
        mask[min_y:max_y, min_x:max_x] = np.maximum(mask[min_y:max_y, min_x:max_x], influence)
    target = np.asarray(color, dtype=np.float32)
    array[..., :3] = array[..., :3] * (1.0 - mask[..., None]) + target[None, None, :] * mask[..., None]


def smoothstep(value):
    value = np.clip(value, 0.0, 1.0)
    return value * value * (3.0 - 2.0 * value)


def draw_mouth(array: np.ndarray) -> None:
    """No painted lip line or lip shading.

    The mouth reads from the FaceMouth inner mouth plus the ARKit-driven lip
    geometry; the skin around the opening is left as clean skin.
    """
    height, width = array.shape[:2]
    sample = array[int(0.705 * height) : int(0.735 * height), int(0.45 * width) : int(0.55 * width), :3]
    skin = sample.mean(axis=(0, 1))
    draw_ellipse(array, 0.5, 0.752, 0.105, 0.050, skin, feather=0.20, strength=1.0)



def repaint_mouth_inner(array: np.ndarray) -> np.ndarray:
    """Coral mouth interior + pink tongue for the FaceMouth mesh.

    The mesh samples different parts of _01 as the ARKit mouth opens, so the
    whole atlas is made into a soft coral interior instead of the base peach
    shapes.
    """
    out = array.copy()
    out[..., :3] = np.array([0.42, 0.18, 0.17], dtype=np.float32)
    return out


def draw_hair_clip(array: np.ndarray) -> None:
    """Add a subtle hoodie pocket and drawstrings on the front shirt half."""
    height, width = array.shape[:2]
    # Front shirt is the upper half of the 1024x2048 atlas.
    # Pocket: a slightly darker rounded rectangle near the lower front.
    x0, x1 = int(width * 0.40), int(width * 0.60)
    y0, y1 = int(height * 0.24), int(height * 0.33)
    shade = PALETTE["hoodieBottom"] * 0.94
    alpha = array[..., 3]
    region = (slice(y0, y1), slice(x0, x1))
    mask = alpha[region] > 0.5
    array[..., :3][region] = np.where(
        mask[..., None],
        array[..., :3][region] * 0.96 + shade[None, None, :] * 0.04,
        array[..., :3][region],
    )
    # Drawstrings: two short vertical white strips below the collar.
    for cx in (0.472, 0.528):
        x = int(width * cx)
        ys = np.arange(int(height * 0.13), int(height * 0.22))
        xs = np.arange(x - 3, x + 4)
        for y in ys:
            for xx in xs:
                if 0 <= y < height and 0 <= xx < width and alpha[y, xx] > 0.5:
                    array[y, xx, :3] = PALETTE["sock"]


def repaint_iris(array: np.ndarray) -> np.ndarray:
    height, width = array.shape[:2]
    alpha = array[..., 3]
    out = array.copy()
    mask = alpha > 0.05
    cols = np.where(mask.any(axis=0))[0]
    if len(cols) == 0:
        return array
    split = int((cols.min() + cols.max()) / 2)
    for eye_index, (x0, x1) in enumerate(((int(cols.min()), split), (split + 1, int(cols.max()) + 1))):
        if x1 <= x0:
            continue
        sub = mask[:, x0:x1]
        rows = np.where(sub.any(axis=1))[0]
        if len(rows) == 0:
            continue
        y0, y1 = int(rows.min()), int(rows.max()) + 1
        cx = (x0 + x1 - 1) / 2.0
        cy = (y0 + y1 - 1) / 2.0
        ry = (y1 - y0) / 2.0

        # The usable iris is only the outer half of each texture region; the
        # inner half is hidden under the eye geometry.  Drawing the pupil at
        # the region center (the inner edge) made the gaze read cross-eyed.
        eye_half = 0.25 if eye_index == 0 else 0.75
        gx = x0 + (x1 - x0) * eye_half
        eye_rx = (x1 - x0) * 0.25
        rx = (x1 - x0) / 2.0

        # Repaint the whole iris cleanly (removes the base split-pupil marks).
        for y in range(y0, y1):
            ty = (y - y0) / max(y1 - y0 - 1, 1)
            if ty < 0.5:
                base = lerp(PALETTE["irisTop"], PALETTE["irisCenter"], ty / 0.5)
            else:
                base = lerp(PALETTE["irisCenter"], PALETTE["irisBottom"], (ty - 0.5) / 0.5)
            for x in range(x0, x1):
                if not mask[y, x]:
                    continue
                nx = (x - gx) / max(rx, 1.0)
                ny = (y - cy) / max(ry, 1.0)
                radius = (nx * nx + ny * ny) ** 0.5
                if radius > 0.92:
                    color = PALETTE["irisOutline"]
                else:
                    color = base
                out[y, x, :3] = color

        # Complete dark pupil, centred in the visible half of the iris.  A
        # final 5 texture-pixel nudge toward the nose is ~2 rendered pixels.
        pupil_shift = 5.0 if eye_index == 0 else -5.0
        draw_ellipse(
            out,
            (gx + pupil_shift) / width,
            cy / height,
            (0.36 * eye_rx) / width,
            (0.52 * ry) / height,
            np.array([0.20, 0.11, 0.07], dtype=np.float32),
            feather=0.10,
            strength=1.0,
        )

        # The reference has the same light direction on both eyes: a large
        # highlight upper-left and a small one lower-right in image space.
        draw_ellipse(
            out,
            (gx - 0.35 * eye_rx) / width,
            (cy - 0.50 * ry) / height,
            (0.45 * eye_rx) / width,
            (0.20 * ry) / height,
            np.array([1.0, 0.99, 0.95], dtype=np.float32),
            feather=0.08,
            strength=0.95,
        )
        draw_ellipse(
            out,
            (gx + 0.32 * eye_rx) / width,
            (cy + 0.38 * ry) / height,
            (0.10 * eye_rx) / width,
            (0.07 * ry) / height,
            np.array([1.0, 1.0, 1.0], dtype=np.float32),
            feather=0.10,
            strength=0.82,
        )
    return out
def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # --- skin ------------------------------------------------------------
    face = load_image("_04")
    face = colorize(face, PALETTE["skinBase"], power=0.9, low=0.55, high=1.0)
    add_radial_blush(face, 0.27, 0.62, 0.11, 0.08, PALETTE["blush"], 0.55)
    add_radial_blush(face, 0.73, 0.62, 0.11, 0.08, PALETTE["blush"], 0.55)
    draw_mouth(face)
    save_image("_04", face)

    inner_mouth = load_image("_01")
    save_image("_01", repaint_mouth_inner(inner_mouth))

    body = load_image("_10")
    body_brightness = luma(body[..., :3])
    # The hands/feet were visibly darker than the face; flatten the baked
    # shading more aggressively so exposed skin matches the face.
    body_colored = colorize(body, PALETTE["skinBase"], power=0.62, low=0.80, high=1.0)
    dark = (body_brightness < 0.08) & (body[..., 3] > 0.5)
    body_colored[..., :3][dark] = body[..., :3][dark]
    fill_transparent(body_colored, PALETTE["skinBase"])
    save_image("_10", body_colored)

    # --- eyes ------------------------------------------------------------
    iris = load_image("_02")
    save_image("_02", repaint_iris(iris))

    eye_white = load_image("_06")
    white = luma(eye_white[..., :3]) > 0.9
    eye_white[..., :3][white] = PALETTE["eyeWhite"]
    save_image("_06", eye_white)

    brow = load_image("_07")
    save_image("_07", colorize(brow, np.array([0.78, 0.68, 0.63], dtype=np.float32), power=0.8, low=0.6, high=1.2))

    eyeline = load_image("_09")
    save_image("_09", colorize(eyeline, np.array([0.36, 0.24, 0.20], dtype=np.float32), power=0.8, low=0.55, high=1.2))

    # --- hair ------------------------------------------------------------
    def hair_color(t, _x, _l):
        height, width = t.shape
        color = np.empty((height, width, 3), dtype=np.float32)
        root, mid, tip = PALETTE["hairRoot"], PALETTE["hairMid"], PALETTE["hairTip"]
        first = t < 0.5
        color[first] = lerp(root, mid, (t[first] / 0.5)[:, None]) if np.any(first) else color[first]
        second = (t >= 0.5) & (t < 0.78)
        color[second] = mid
        third = t >= 0.78
        color[third] = lerp(mid, tip, ((t[third] - 0.78) / 0.22)[:, None])
        return color

    hair = load_image("_16")
    hair = colorize_gradient(hair, hair_color, power=0.35, low=0.88, high=1.0)
    lighten_hair_root(hair)
    save_image("_16", hair)

    hairback = load_image("_12")
    hairback = colorize_gradient(hairback, hair_color, power=0.35, low=0.88, high=1.0)
    hairback = lighten_hair_root(hairback)
    fill_transparent(hairback, PALETTE["hairMid"])
    save_image("_12", hairback)

    # --- clothes ---------------------------------------------------------
    def top_color(t, _x, _l):
        height, width = t.shape
        color = np.empty((height, width, 3), dtype=np.float32)
        white, blue = PALETTE["hoodieTop"], PALETTE["hoodieBottom"]
        blend = np.clip((t - 0.55) / 0.45, 0.0, 1.0)
        color[:] = lerp(white, blue, blend)[..., None].transpose(0, 1, 2) if False else white
        color = white[None, None, :] * (1.0 - blend[..., None]) + blue[None, None, :] * blend[..., None]
        return color

    top = load_image("_14")
    top = colorize_gradient(top, top_color, power=0.9, low=0.7, high=1.0)
    draw_hair_clip(top)
    fill_transparent(top, PALETTE["hoodieTop"])
    save_image("_14", top)

    shorts = load_image("_13")
    shorts = colorize(shorts, PALETTE["shorts"], power=0.9, low=0.65, high=1.0)
    # White hem along the bottom edge of each opaque shorts column.
    mask = shorts[..., 3] > 0.5
    for x in range(shorts.shape[1]):
        rows = np.where(mask[:, x])[0]
        if len(rows) < 4:
            continue
        bottom = rows.max()
        shorts[max(0, bottom - 5) : bottom + 1, x, :3] = PALETTE["sock"]
    fill_transparent(shorts, PALETTE["shorts"])
    save_image("_13", shorts)

    shoes = load_image("_15")
    brightness = luma(shoes[..., :3])
    shoes_colored = colorize(shoes, PALETTE["shoeBase"], power=0.9, low=0.7, high=1.0)
    accent = brightness < 0.9
    shoes_colored[..., :3][accent] = np.clip(
        shoes_colored[..., :3][accent] * 0.35 + PALETTE["shoeAccent"][None, :] * 0.65, 0.0, 1.0
    )
    save_image("_15", shoes_colored)

    # --- new accessory textures -----------------------------------------
    size = 256
    yy, xx = np.mgrid[0:size, 0:size]
    ty = yy / (size - 1)
    tx = xx / (size - 1)
    outer = np.ones((size, size, 4), dtype=np.float32)
    outer[..., :3] = (
        PALETTE["hairRoot"][None, None, :] * (1.0 - ty[..., None])
        + PALETTE["hairTip"][None, None, :] * ty[..., None]
    )
    border = 12
    rim = PALETTE["hairTip"] * 0.82
    outer[:border, :, :3] = rim
    outer[-border:, :, :3] = rim
    outer[:, :border, :3] = rim
    outer[:, -border:, :3] = rim
    save_image("ear_outer", outer)

    inner = np.ones((size, size, 4), dtype=np.float32)
    diagonal = np.clip((tx * 0.55 + ty * 0.45), 0.0, 1.0)
    inner[..., :3] = (
        PALETTE["earInnerStart"][None, None, :] * (1.0 - diagonal[..., None])
        + PALETTE["earInnerEnd"][None, None, :] * diagonal[..., None]
    )
    add_radial_blush(inner, 0.52, 0.42, 0.22, 0.22, np.array([0.96, 0.82, 0.90], dtype=np.float32), 0.35)
    inner_rim = PALETTE["earInnerEnd"] * 0.7
    inner[:border, :, :3] = inner_rim
    inner[-border:, :, :3] = inner_rim
    inner[:, :border, :3] = inner_rim
    inner[:, -border:, :3] = inner_rim
    save_image("ear_inner", inner)

    # --- ahoge gradient --------------------------------------------------
    ahoge_w, ahoge_h = 64, 256
    yy, _xx = np.mgrid[0:ahoge_h, 0:ahoge_w]
    t = yy / (ahoge_h - 1)
    ahoge_root = np.array([0.847, 0.875, 0.918], dtype=np.float32)   # #D8DFEA
    ahoge_mid = np.array([0.788, 0.831, 0.894], dtype=np.float32)    # #C9D4E4
    ahoge_tip = np.array([0.686, 0.761, 0.855], dtype=np.float32)    # #AFC2DA
    ahoge = np.ones((ahoge_h, ahoge_w, 4), dtype=np.float32)
    first = t < 0.55
    second = ~first
    ahoge[..., :3][first] = lerp(ahoge_root, ahoge_mid, (t[first] / 0.55)[:, None])
    ahoge[..., :3][second] = lerp(ahoge_mid, ahoge_tip, ((t[second] - 0.55) / 0.45)[:, None])
    save_image("ahoge", ahoge)

    # Leave _03 highlight, _05/_11 normals, _17 emissive, hair normals as base.
    print(f"TEXTURES -> {OUT_DIR}")
    for path in sorted(OUT_DIR.glob("*.png")):
        print(f"TEXTURE {path.name} {path.stat().st_size} bytes")


main()
