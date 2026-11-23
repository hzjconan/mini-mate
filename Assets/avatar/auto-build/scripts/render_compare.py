"""Render Phase 0 review images and a local review.html.

Run:
    blender --background --factory-startup --python scripts/render_compare.py -- quick
    blender --background --factory-startup --python scripts/render_compare.py
"""

from __future__ import annotations

import html
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
CONFIG = json.loads((ROOT / "config" / "avatar.json").read_text(encoding="utf-8"))
BLEND = ROOT / "work" / "phase0" / "minimate_phase0.blend"
OUT = ROOT / "renders" / "phase0"
REFERENCE = ROOT.parent / "reference"


def parse_quick() -> bool:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return "quick" in argv


def world_bounds(objects) -> tuple[Vector, Vector]:
    minimum = Vector((1e9, 1e9, 1e9))
    maximum = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            minimum = Vector(min(minimum[i], point[i]) for i in range(3))
            maximum = Vector(max(maximum[i], point[i]) for i in range(3))
    return minimum, maximum


def look_at(obj, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def setup_scene(quick: bool) -> tuple[bpy.types.Object, Vector, Vector, Vector]:
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.fps = 30
    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "None"
    except Exception:  # noqa: BLE001 - different Blender color management names
        pass

    world = bpy.data.worlds.new("ReviewWorld") if not bpy.data.worlds else bpy.data.worlds[0]
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.86, 0.87, 0.91, 1.0)
        background.inputs[1].default_value = 1.0

    for name, location, energy, size in (
        ("Key", (2.2, -3.2, 3.2), 320, 3.0),
        ("Fill", (-3.0, -2.0, 1.8), 130, 3.0),
        ("Rim", (0.5, 2.8, 3.0), 220, 2.5),
    ):
        light_data = bpy.data.lights.new(name, type="AREA")
        light_data.energy = energy
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        scene.collection.objects.link(light)
        light.location = location
        look_at(light, Vector((0, 0, 1.0)))

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    scene.collection.objects.link(camera)
    camera_data.type = "ORTHO"
    camera_data.sensor_fit = "VERTICAL"
    scene.camera = camera

    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    minimum, maximum = world_bounds(meshes)
    center = (minimum + maximum) / 2.0
    height = maximum.z - minimum.z
    width = maximum.x - minimum.x
    print(f"REVIEW_BOUNDS min={tuple(round(v,3) for v in minimum)} max={tuple(round(v,3) for v in maximum)} height={height:.3f} width={width:.3f}")
    return camera, center, minimum, maximum


def set_full_camera(camera, center: Vector, minimum: Vector, maximum: Vector) -> None:
    height = maximum.z - minimum.z
    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.ortho_scale = height * 1.12
    camera.location = (center.x, center.y - 5.0, center.z)
    look_at(camera, center)


def set_view_camera(camera, center: Vector, minimum: Vector, maximum: Vector, view: str) -> None:
    height = maximum.z - minimum.z
    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.ortho_scale = height * 1.12
    if view == "front":
        camera.location = (center.x, center.y - 5.0, center.z)
    elif view == "side":
        camera.location = (center.x + 5.0, center.y, center.z)
    else:
        camera.location = (center.x, center.y + 5.0, center.z)
    look_at(camera, center)


def set_face_camera(camera, face, hair) -> None:
    minimum, maximum = world_bounds([face, hair])
    center = (minimum + maximum) / 2.0
    height = maximum.z - minimum.z
    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.ortho_scale = height * 1.18
    camera.location = (center.x, center.y - 5.0, center.z + height * 0.02)
    look_at(camera, center)


def set_head_camera(camera, objects) -> None:
    minimum, maximum = world_bounds(objects)
    center = (minimum + maximum) / 2.0
    height = maximum.z - minimum.z
    camera.data.type = "ORTHO"
    camera.data.sensor_fit = "VERTICAL"
    camera.data.ortho_scale = height * 1.18
    camera.location = (center.x, center.y - 5.0, center.z)
    look_at(camera, center)


def render_still(camera, scene, path: Path, width: int, height: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    scene.camera = camera
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {path}")


def load_rgba(path: Path) -> np.ndarray:
    image = bpy.data.images.load(str(path))
    width, height = image.size
    pixels = np.empty(width * height * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    array = pixels.reshape(height, width, 4)[::-1].copy()
    bpy.data.images.remove(image)
    return array


def save_rgba(path: Path, array: np.ndarray) -> None:
    height, width = array.shape[:2]
    image = bpy.data.images.new(name=path.stem, width=width, height=height, alpha=True, float_buffer=False)
    image.colorspace_settings.name = "sRGB"
    image.alpha_mode = "STRAIGHT"
    image.pixels.foreach_set(np.ascontiguousarray(array[::-1].reshape(-1).astype(np.float32)))
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def resize_bilinear(array: np.ndarray, width: int, height: int) -> np.ndarray:
    source_h, source_w = array.shape[:2]
    ys = np.linspace(0, source_h - 1, height)
    xs = np.linspace(0, source_w - 1, width)
    y0 = np.floor(ys).astype(int)
    x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, source_h - 1)
    x1 = np.minimum(x0 + 1, source_w - 1)
    fy = (ys - y0)[:, None, None]
    fx = (xs - x0)[None, :, None]
    top = array[y0][:, x0] * (1 - fx) + array[y0][:, x1] * fx
    bottom = array[y1][:, x0] * (1 - fx) + array[y1][:, x1] * fx
    return top * (1 - fy) + bottom * fy


def tile_images(paths: list[Path], columns: int, tile_width: int, tile_height: int, output: Path) -> None:
    rows = math.ceil(len(paths) / columns)
    canvas = np.ones((rows * tile_height, columns * tile_width, 4), dtype=np.float32)
    for index, path in enumerate(paths):
        array = resize_bilinear(load_rgba(path), tile_width, tile_height)
        row, column = divmod(index, columns)
        canvas[row * tile_height : (row + 1) * tile_height, column * tile_width : (column + 1) * tile_width] = array
    save_rgba(output, canvas)
    print(f"TILED {output}")


def make_comparison(reference_path: Path, crop: tuple[float, float], model_path: Path, output: Path) -> None:
    reference = load_rgba(reference_path)
    height, width = reference.shape[:2]
    x0, x1 = int(width * crop[0]), int(width * crop[1])
    crop_array = reference[:, x0:x1]
    model = load_rgba(model_path)
    target_height = model.shape[0]
    target_width = max(1, int(crop_array.shape[1] * target_height / crop_array.shape[0]))
    reference_scaled = resize_bilinear(crop_array, target_width, target_height)
    gap = 20
    canvas = np.ones((target_height, target_width + gap + model.shape[1], 4), dtype=np.float32)
    canvas[:, :target_width] = reference_scaled
    canvas[:, target_width + gap :] = model
    save_rgba(output, canvas)
    print(f"COMPARISON {output}")


def set_expression(face, weights: dict[str, float]) -> None:
    keys = face.data.shape_keys.key_blocks
    for key in keys:
        if key.name != "Basis":
            key.value = 0.0
    for name, value in weights.items():
        key = keys.get(name)
        if key:
            key.value = value


def expression_presets() -> dict[str, dict[str, float]]:
    return {
        "happy": {"mouthSmileLeft": 0.85, "mouthSmileRight": 0.85, "jawOpen": 0.2, "cheekSquintLeft": 0.4, "cheekSquintRight": 0.4, "browInnerUp": 0.3},
        "gentle": {"mouthSmileLeft": 0.5, "mouthSmileRight": 0.5, "eyeSquintLeft": 0.2, "eyeSquintRight": 0.2},
        "sad": {"mouthFrownLeft": 0.6, "mouthFrownRight": 0.6, "browInnerUp": 0.7, "eyeSquintLeft": 0.3, "eyeSquintRight": 0.3},
        "surprised": {"jawOpen": 0.5, "eyeWideLeft": 0.6, "eyeWideRight": 0.6, "browOuterUpLeft": 0.5, "browOuterUpRight": 0.5},
        "shy": {"mouthSmileLeft": 0.4, "mouthSmileRight": 0.4, "eyeSquintLeft": 0.5, "eyeSquintRight": 0.5},
        "playful": {"tongueOut": 0.5, "mouthSmileLeft": 0.6, "mouthSmileRight": 0.6, "eyeSquintLeft": 0.3, "eyeSquintRight": 0.3},
        "concerned": {"mouthFrownLeft": 0.3, "mouthFrownRight": 0.3, "browDownLeft": 0.4, "browDownRight": 0.4, "browInnerUp": 0.4},
        "neutral": {},
    }


def render_expressions(camera, scene, face, hair) -> list[Path]:
    set_face_camera(camera, face, hair)
    directory = OUT / "expressions"
    directory.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, weights in expression_presets().items():
        set_expression(face, weights)
        path = directory / f"{name}.png"
        render_still(camera, scene, path, 512, 512)
        paths.append(path)
    set_expression(face, {})
    return paths


def render_actions(camera, scene, armature, center, minimum, maximum) -> list[Path]:
    set_full_camera(camera, center, minimum, maximum)
    directory = OUT / "actions"
    directory.mkdir(parents=True, exist_ok=True)
    paths = []
    armature.animation_data_create()
    for tag in ("nod", "wave", "spin", "heart", "shyCover", "leanBack", "lookAround", "notice"):
        action = bpy.data.actions.get(tag)
        if not action:
            continue
        armature.animation_data.action = action
        start, end = action.frame_range
        frames = [int(round(start + (end - start) * t)) for t in (0.0, 0.33, 0.66, 1.0)]
        for index, frame in enumerate(frames):
            scene.frame_set(frame)
            path = directory / f"{tag}_{index}.png"
            render_still(camera, scene, path, 384, 512)
            paths.append(path)
    armature.animation_data.action = None
    scene.frame_set(1)
    return paths


def render_turntable(camera, scene, armature, center, minimum, maximum) -> None:
    set_full_camera(camera, center, minimum, maximum)
    directory = OUT / "turntable"
    directory.mkdir(parents=True, exist_ok=True)
    armature.animation_data_create()
    armature.animation_data.action = None
    base_rotation = armature.rotation_euler.copy()
    frames = 24
    for index in range(frames):
        armature.rotation_euler = base_rotation
        armature.rotation_euler.z = 2.0 * math.pi * index / frames
        scene.frame_set(1)
        render_still(camera, scene, directory / f"frame_{index:03d}.png", 512, 640)
    armature.rotation_euler = base_rotation


def write_review_html(expression_paths: list[Path], action_paths: list[Path], quick: bool) -> None:
    def rel(path: Path) -> str:
        return path.relative_to(OUT).as_posix()

    features = [
        "头身比约 1:2.5，头大、四肢短",
        "银白→淡蓝渐变 bob，发尾到下颌",
        "猫耳发箍（耳朵 + 内耳渐变 + 侧面连接件）",
        "头顶呆毛，向右侧弯",
        "琥珀色大眼、虹膜占眼高约 70%、两点高光",
        "细平眉、颜色比头发深一档",
        "小鼻、ω 形小嘴",
        "脸型圆润、脸颊饱满、下巴短（Phase 2）",
        "肤色 #F7DCD3、阴影 #E8BFB4、腮红 #F3B3AD",
        "白蓝渐变连帽衫、白色抽绳、口袋",
        "浅蓝短裤、白色裤脚边",
        "白袜、白/蓝灰运动鞋",
        "柔和 pastel 质感",
    ]
    feature_html = "\n".join(
        f'<li><label><input type="checkbox"> {html.escape(item)}</label></li>' for item in features
    )
    expression_html = ""
    if expression_paths:
        items = "\n".join(
            f'<figure><img src="{rel(path)}" alt="{path.stem}"><figcaption>{path.stem}</figcaption></figure>'
            for path in expression_paths
        )
        expression_html = f'<section><h2>表情冒烟</h2><div class="grid expressions">{items}</div></section>'
    action_html = ""
    if action_paths:
        items = "\n".join(
            f'<figure><img src="{rel(path)}" alt="{path.stem}"><figcaption>{path.stem}</figcaption></figure>'
            for path in action_paths
        )
        action_html = f'<section><h2>8 动作抽帧</h2><div class="grid actions">{items}</div></section>'

    extras_html = ""
    if (OUT / "turntable_sheet.png").exists():
        extras_html += (
            '<section><h2>转台</h2><figure><img src="turntable_sheet.png" alt="turntable">'
            '<figcaption>24 帧 360° 转台</figcaption></figure></section>'
        )
    if (OUT / "usd_preview_front.png").exists():
        extras_html += (
            '<section><h2>USDZ PBR 预览</h2><div class="reference">'
            '<figure><img src="usd_preview_front.png" alt="USDZ front"><figcaption>USDZ 正面（usdrecord 近似）</figcaption></figure>'
            '<figure><img src="usd_preview_back.png" alt="USDZ back"><figcaption>USDZ 背面（usdrecord 近似）</figcaption></figure>'
            '</div></section>'
        )

    review_path = OUT / "review.html"
    review_path.write_text(
        f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>小瓜 Phase 0 审核</title>
<style>
  :root {{ color-scheme: light; --ink: #1f2430; --muted: #6b7280; --line: #d9dee8; --bg: #f7f8fb; }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; font: 15px/1.55 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: var(--ink); background: var(--bg); }}
  main {{ max-width: 1180px; margin: 0 auto; padding: 32px 20px 80px; }}
  h1 {{ font-size: 26px; margin: 0 0 6px; }}
  h2 {{ font-size: 18px; margin: 28px 0 12px; padding-bottom: 8px; border-bottom: 1px solid var(--line); }}
  p {{ color: var(--muted); }}
  .compare {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }}
  figure {{ margin: 0; background: white; border: 1px solid var(--line); border-radius: 10px; padding: 8px; }}
  figure img {{ width: 100%; display: block; border-radius: 6px; }}
  figcaption {{ color: var(--muted); font-size: 12px; padding-top: 6px; text-align: center; }}
  .reference {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }}
  .grid {{ display: grid; gap: 10px; }}
  .grid.expressions {{ grid-template-columns: repeat(4, 1fr); }}
  .grid.actions {{ grid-template-columns: repeat(4, 1fr); }}
  ul.checklist {{ list-style: none; padding: 0; display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px 18px; }}
  ul.checklist li {{ background: white; border: 1px solid var(--line); border-radius: 8px; padding: 8px 10px; }}
  label {{ display: flex; gap: 8px; align-items: flex-start; }}
  input[type=checkbox] {{ margin-top: 4px; }}
  .badge {{ display: inline-block; background: #eef2ff; color: #4356a0; border-radius: 999px; padding: 2px 9px; font-size: 12px; margin-right: 6px; }}
  .note {{ background: white; border: 1px solid var(--line); border-radius: 10px; padding: 14px 16px; }}
</style>
</head>
<body>
<main>
<h1>小瓜 Phase 0 审核</h1>
<p><span class="badge">Phase 0</span>自动换贴图 + Q 版比例 + 猫耳发箍 / 呆毛。连帽衫几何在 Phase 1。</p>
<p><a href="scorecard.html" style="display:inline-block;background:#4356a0;color:#fff;text-decoration:none;border-radius:8px;padding:9px 12px">打开 0–3 分评分表</a> <span style="color:#6b7280;font-size:13px">评分只保存在本页浏览器，不会写入仓库。</span></p>

<section>
<h2>设计参考</h2>
<div class="reference">
  <figure><img src="../../../reference/three-view.jpg" alt="three-view"><figcaption>three-view.jpg</figcaption></figure>
  <figure><img src="../../../reference/expression-sheet.jpg" alt="expression-sheet"><figcaption>expression-sheet.jpg</figcaption></figure>
</div>
</section>

<section>
<h2>三视图对比</h2>
<div class="compare">
  <figure><img src="compare_front.png" alt="front"><figcaption>正面：左参考 / 右模型</figcaption></figure>
  <figure><img src="compare_side.png" alt="side"><figcaption>侧面：左参考 / 右模型</figcaption></figure>
  <figure><img src="compare_back.png" alt="back"><figcaption>背面：左参考 / 右模型</figcaption></figure>
</div>
</section>

<section>
<h2>脸部特写</h2>
<div class="reference">
  <figure><img src="face_closeup.png" alt="face closeup"><figcaption>face_closeup.png</figcaption></figure>
  <figure><img src="head_closeup.png" alt="head closeup"><figcaption>head_closeup.png（含猫耳/呆毛）</figcaption></figure>
</div>
</section>

{expression_html}
{action_html}
{extras_html}

<section>
<h2>设计特征清单</h2>
<ul class="checklist">
{feature_html}
</ul>
</section>

<section>
<h2>审核口径</h2>
<div class="note">
<p>每个特征 0–3 分：0 缺失、1 明显不同、2 接近但有瑕疵、3 在 App 常用尺寸下一致。关键特征不得有 0/1；整体平均 ≥ 2.5 且你确认，才进入下一 phase。</p>
<p>自动门禁结果见 <a href="../../reports/validation-phase0.md">reports/validation-phase0.md</a>。候选 USDZ：<a href="../../out/minimate_phase0.usdz">out/minimate_phase0.usdz</a>，可在 Finder 中按空格 Quick Look 旋转；Quick Look 只用于看外形，不用于形态键/动作验收。</p>
</div>
</section>
</main>
</body>
</html>
""",
        encoding="utf-8",
    )
    print(f"REVIEW_HTML {review_path}")


def main() -> None:
    quick = parse_quick()
    OUT.mkdir(parents=True, exist_ok=True)
    camera, center, minimum, maximum = setup_scene(quick)
    face = bpy.data.objects.get("Face")
    hair = bpy.data.objects.get("Hair001")
    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene

    set_view_camera(camera, center, minimum, maximum, "front")
    render_still(camera, scene, OUT / "model_front.png", 768, 1024)
    set_view_camera(camera, center, minimum, maximum, "side")
    render_still(camera, scene, OUT / "model_side.png", 768, 1024)
    set_view_camera(camera, center, minimum, maximum, "back")
    render_still(camera, scene, OUT / "model_back.png", 768, 1024)

    set_face_camera(camera, face, hair)
    render_still(camera, scene, OUT / "face_closeup.png", 1024, 1024)
    head_objects = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name in {"Face", "Hair001", "CatEarR", "CatEarL", "CatEarInnerR", "CatEarInnerL", "Ahoge", "Headband", "HeadbandSideL", "HeadbandSideR", "HeadbandAccentL", "HeadbandAccentR"}]
    set_head_camera(camera, head_objects)
    render_still(camera, scene, OUT / "head_closeup.png", 1024, 1024)

    make_comparison(REFERENCE / "three-view.jpg", (0.0, 0.333), OUT / "model_side.png", OUT / "compare_side.png")
    make_comparison(REFERENCE / "three-view.jpg", (0.333, 0.666), OUT / "model_front.png", OUT / "compare_front.png")
    make_comparison(REFERENCE / "three-view.jpg", (0.666, 1.0), OUT / "model_back.png", OUT / "compare_back.png")

    expression_paths: list[Path] = []
    action_paths: list[Path] = []
    if not quick:
        expression_paths = render_expressions(camera, scene, face, hair)
        tile_images(expression_paths, 4, 384, 384, OUT / "expression_grid.png")
        set_full_camera(camera, center, minimum, maximum)
        action_paths = render_actions(camera, scene, armature, center, minimum, maximum)
        tile_images(action_paths, 4, 288, 384, OUT / "actions_contact_sheet.png")
        render_turntable(camera, scene, armature, center, minimum, maximum)
        frames = sorted((OUT / "turntable").glob("frame_*.png"))
        if frames:
            tile_images(frames, 6, 256, 320, OUT / "turntable_sheet.png")
    write_review_html(expression_paths, action_paths, quick)
    print(f"REVIEW_READY {OUT / 'review.html'}")


main()
