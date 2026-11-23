"""Audit the base VRM and extract its packed textures.

Run:
    blender --background --factory-startup --python scripts/audit_base.py

Outputs:
    work/base/audit.json
    work/base/textures/*.png
    reports/baseline-audit.md
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "avatar.json"
WORK_DIR = ROOT / "work" / "base"
TEXTURE_DIR = WORK_DIR / "textures"
REPORT_PATH = ROOT / "reports" / "baseline-audit.md"

ADDON_CANDIDATES = ("bl_ext.user_default.vrm", "VRM_Addon_for_Blender")
ARKIT_SWIFT = ROOT.parent.parent.parent / "Packages" / "MiniMateKit" / "Sources" / "MMAvatar" / "BlendShapeIndex.swift"


def load_config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def enable_vrm_addon() -> str:
    for module in ADDON_CANDIDATES:
        try:
            bpy.ops.preferences.addon_enable(module=module)
            return module
        except Exception:  # noqa: BLE001 - try next candidate
            continue
    raise SystemExit("找不到 VRM 插件，请先安装 VRM Add-on for Blender")


def arkit_names() -> list[str]:
    if ARKIT_SWIFT.exists():
        text = ARKIT_SWIFT.read_text(encoding="utf-8")
        match = re.search(r"arkitNames:\s*\[String\]\s*=\s*\[(.*?)\]", text, re.S)
        if match:
            return re.findall(r'"([^"]+)"', match.group(1))
    raise SystemExit(f"无法从 {ARKIT_SWIFT} 解析 ARKit 名称")


def world_bounds(objects) -> dict:
    minimum = Vector((1e9, 1e9, 1e9))
    maximum = Vector((-1e9, -1e9, -1e9))
    for obj in objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            minimum = Vector(min(minimum[i], point[i]) for i in range(3))
            maximum = Vector(max(maximum[i], point[i]) for i in range(3))
    return {
        "min": [round(value, 4) for value in minimum],
        "max": [round(value, 4) for value in maximum],
        "height": round(maximum.z - minimum.z, 4),
    }


def safe_filename(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


def save_image(image, directory: Path) -> str | None:
    if image.size[0] == 0 or image.size[1] == 0:
        return None
    if image.name in {"Render Result", "Viewer Node"}:
        return None
    path = directory / f"{safe_filename(image.name)}.png"
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()
    return str(path.relative_to(ROOT))


def collect_material_images(material) -> list[str]:
    names: list[str] = []
    if not material.use_nodes or material.node_tree is None:
        return names
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            if node.image.name not in names:
                names.append(node.image.name)
    return names


def main() -> None:
    config = load_config()
    vrm_path = (ROOT / config["source"]["vrm"]).resolve()
    if not vrm_path.exists():
        raise SystemExit(f"底座 VRM 不存在: {vrm_path}")

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon = enable_vrm_addon()
    bpy.ops.import_scene.vrm(filepath=str(vrm_path))

    scene_objects = list(bpy.context.scene.objects)
    meshes = [obj for obj in scene_objects if obj.type == "MESH"]
    armatures = [obj for obj in scene_objects if obj.type == "ARMATURE"]
    expected_arkit = arkit_names()

    objects_info = []
    for obj in scene_objects:
        info = {
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else None,
            "vertex_groups": [group.name for group in obj.vertex_groups] if obj.type == "MESH" else [],
        }
        if obj.type == "MESH":
            info.update(
                {
                    "vertices": len(obj.data.vertices),
                    "polygons": len(obj.data.polygons),
                    "loops": len(obj.data.loops),
                    "materials": [
                        slot.material.name if slot.material else None
                        for slot in obj.material_slots
                    ],
                    "uv_layers": [layer.name for layer in obj.data.uv_layers],
                    "modifiers": [
                        {"name": modifier.name, "type": modifier.type}
                        for modifier in obj.modifiers
                    ],
                    "shape_keys": (
                        [key.name for key in obj.data.shape_keys.key_blocks]
                        if obj.data.shape_keys
                        else []
                    ),
                }
            )
        objects_info.append(info)

    materials_info = []
    for material in bpy.data.materials:
        materials_info.append(
            {
                "name": material.name,
                "users": material.users,
                "images": collect_material_images(material),
            }
        )

    images_info = []
    for image in bpy.data.images:
        saved = save_image(image, TEXTURE_DIR)
        images_info.append(
            {
                "name": image.name,
                "size": list(image.size),
                "filepath": image.filepath,
                "packed": bool(image.packed_file),
                "saved_as": saved,
            }
        )

    armatures_info = []
    for armature in armatures:
        bones = []
        for bone in armature.data.bones:
            bones.append(
                {
                    "name": bone.name,
                    "parent": bone.parent.name if bone.parent else None,
                    "head": [round(value, 4) for value in bone.head_local],
                    "tail": [round(value, 4) for value in bone.tail_local],
                    "use_deform": bone.use_deform,
                }
            )
        armatures_info.append(
            {
                "name": armature.name,
                "bone_count": len(bones),
                "bones": bones,
            }
        )

    face_objects = []
    for obj in meshes:
        if not obj.data.shape_keys:
            continue
        available = [key.name for key in obj.data.shape_keys.key_blocks if key.name != "Basis"]
        missing = [name for name in expected_arkit if name not in available]
        face_objects.append(
            {
                "mesh": obj.name,
                "key_blocks": len(obj.data.shape_keys.key_blocks),
                "targets": len(available),
                "arkit_expected": len(expected_arkit),
                "arkit_present": len(expected_arkit) - len(missing),
                "arkit_missing": missing,
            }
        )

    audit = {
        "source_vrm": str(vrm_path),
        "blender_version": bpy.app.version_string,
        "vrm_addon": addon,
        "bounds": world_bounds(meshes),
        "objects": objects_info,
        "materials": materials_info,
        "images": images_info,
        "armatures": armatures_info,
        "shape_key_audit": face_objects,
        "expected_arkit": expected_arkit,
    }
    (WORK_DIR / "audit.json").write_text(
        json.dumps(audit, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# 基线素材审计",
        "",
        f"- 源文件：`{vrm_path}`",
        f"- Blender：{bpy.app.version_string}",
        f"- VRM 插件：`{addon}`",
        f"- 尺寸：{audit['bounds']['min']} – {audit['bounds']['max']}，高 {audit['bounds']['height']} m",
        "",
        "## 网格与形态键",
        "",
        "| 网格 | 顶点 | 三角面 | 形态键 | 材质数 |",
        "|---|---:|---:|---:|---:|",
    ]
    for info in objects_info:
        if info["type"] != "MESH":
            continue
        lines.append(
            f"| `{info['name']}` | {info['vertices']} | {info['polygons']} | "
            f"{len(info['shape_keys'])} | {len(info['materials'])} |"
        )

    lines += ["", "## ARKit 52 名称检查", ""]
    if not face_objects:
        lines.append("- 没有发现带形态键的网格。")
    for info in face_objects:
        lines.append(
            f"- `{info['mesh']}`：{info['targets']} 个目标形态键，"
            f"ARKit {info['arkit_present']}/{info['arkit_expected']}，"
            f"缺失：{info['arkit_missing'] or '无'}"
        )

    lines += ["", "## 骨架", ""]
    for info in armatures_info:
        lines.append(f"- `{info['name']}`：{info['bone_count']} 根骨骼")
        for key_name in ("J_Bip_C_Head", "J_Bip_C_Neck", "J_Bip_C_Hips", "J_Bip_L_UpperArm", "J_Bip_R_UpperArm"):
            if any(bone["name"] == key_name for bone in info["bones"]):
                lines.append(f"  - `{key_name}` 存在")

    lines += ["", "## 材质与贴图", ""]
    for info in materials_info:
        if not info["images"]:
            continue
        lines.append(f"- `{info['name']}`：{', '.join('`' + name + '`' for name in info['images'])}")

    lines += [
        "",
        "## 原始贴图",
        "",
        f"已提取到 `{TEXTURE_DIR.relative_to(ROOT)}/`：",
        "",
        "| 图像 | 尺寸 | 保存为 |",
        "|---|---|---|",
    ]
    for info in images_info:
        if not info["saved_as"]:
            continue
        lines.append(f"| `{info['name']}` | {info['size'][0]}×{info['size'][1]} | `{info['saved_as']}` |")

    REPORT_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"AUDIT_JSON {WORK_DIR / 'audit.json'}")
    print(f"AUDIT_REPORT {REPORT_PATH}")
    print(f"TEXTURES {len([i for i in images_info if i['saved_as']])} -> {TEXTURE_DIR}")
    for info in face_objects:
        print(
            f"SHAPEKEYS {info['mesh']} targets={info['targets']} "
            f"arkit={info['arkit_present']}/{info['arkit_expected']} "
            f"missing={info['arkit_missing']}"
        )


main()
