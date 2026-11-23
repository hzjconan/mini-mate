"""Shared helpers for the avatar auto-build pipeline."""

from __future__ import annotations

import json
import math
import os
import shutil
import tempfile
from pathlib import Path

import bpy
from mathutils import Euler

ROOT = Path(__file__).resolve().parent.parent
ADDON_CANDIDATES = ("bl_ext.user_default.vrm", "VRM_Addon_for_Blender")
ACTION_NAMES = (
    "nod",
    "wave",
    "spin",
    "heart",
    "shyCover",
    "leanBack",
    "lookAround",
    "notice",
)


def load_config() -> dict:
    return json.loads((ROOT / "config" / "avatar.json").read_text(encoding="utf-8"))


def enable_vrm_addon() -> str:
    for module in ADDON_CANDIDATES:
        try:
            bpy.ops.preferences.addon_enable(module=module)
            return module
        except Exception:  # noqa: BLE001 - try next candidate
            continue
    raise SystemExit("找不到 VRM 插件，请先安装 VRM Add-on for Blender")


def find_bone(armature, predicate):
    for bone in armature.pose.bones:
        if predicate(bone.name):
            return bone.name
    return None


def make_actions(armature, fps: int = 30) -> dict[str, int]:
    """Create the eight required actions; names match ActionTag.rawValue."""
    armature.animation_data_create()
    head = find_bone(armature, lambda n: n.endswith("Head"))
    spine = find_bone(armature, lambda n: n.endswith("Spine") or n.endswith("Chest"))
    hips = find_bone(armature, lambda n: n.endswith("Hips"))
    right_arm = find_bone(armature, lambda n: "R_UpperArm" in n or "UpperArm.R" in n)
    left_arm = find_bone(armature, lambda n: "L_UpperArm" in n or "UpperArm.L" in n)
    print(f"ACTION_BONES head={head} spine={spine} hips={hips} right={right_arm} left={left_arm}")

    specs = {
        "nod": [
            (0.0, {head: (0, 0, 0)}),
            (0.35, {head: (0.28, 0, 0)}),
            (0.7, {head: (-0.08, 0, 0)}),
            (1.0, {head: (0, 0, 0)}),
        ],
        "wave": [
            (0.0, {right_arm: (0, 0, 0)}),
            (0.35, {right_arm: (0, 0, 0.9)}),
            (0.7, {right_arm: (0, 0, 0.4)}),
            (1.05, {right_arm: (0, 0, 0.9)}),
            (1.4, {right_arm: (0, 0, 0)}),
        ],
        "spin": [
            (0.0, {hips: (0, 0, 0)}),
            (1.6, {hips: (0, 0, 2 * math.pi)}),
        ],
        "heart": [
            (0.0, {left_arm: (0, 0, 0), right_arm: (0, 0, 0)}),
            (0.7, {left_arm: (0.9, 0, 0.5), right_arm: (0.9, 0, -0.5)}),
            (1.4, {left_arm: (0, 0, 0), right_arm: (0, 0, 0)}),
        ],
        "shyCover": [
            (0.0, {left_arm: (0, 0, 0), right_arm: (0, 0, 0)}),
            (0.6, {left_arm: (1.2, 0, 0.6), right_arm: (1.2, 0, -0.6)}),
            (1.4, {left_arm: (0, 0, 0), right_arm: (0, 0, 0)}),
        ],
        "leanBack": [
            (0.0, {spine: (0, 0, 0)}),
            (0.5, {spine: (-0.3, 0, 0)}),
            (1.0, {spine: (0, 0, 0)}),
        ],
        "lookAround": [
            (0.0, {head: (0, 0, 0)}),
            (0.4, {head: (0, 0, 0.5)}),
            (0.8, {head: (0, 0, -0.5)}),
            (1.2, {head: (0, 0, 0)}),
        ],
        "notice": [
            (0.0, {head: (0, 0, 0)}),
            (0.35, {head: (-0.1, 0, 0.2)}),
            (0.8, {head: (0, 0, 0)}),
        ],
    }

    ranges: dict[str, int] = {}
    for tag, keys in specs.items():
        if all(bone is None for _, poses in keys for bone in poses):
            print(f"SKIP_ACTION {tag} 没有匹配到骨骼")
            continue

        action = bpy.data.actions.new(tag)
        action.use_fake_user = True
        armature.animation_data.action = action
        for bone in armature.pose.bones:
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = (1, 0, 0, 0)

        for seconds, poses in keys:
            frame = round(seconds * fps) + 1
            for bone_name, euler in poses.items():
                if bone_name is None:
                    continue
                bone = armature.pose.bones[bone_name]
                bone.rotation_quaternion = Euler(euler, "XYZ").to_quaternion()
                bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)

        ranges[tag] = round(max(seconds for seconds, _ in keys) * fps) + 1
        armature.animation_data.action = None

    print(f"ACTIONS {sorted(ranges)}")
    return ranges


def export_usd(path: str, animated: bool) -> None:
    properties = set(bpy.ops.wm.usd_export.get_rna_type().properties.keys())
    kwargs = {
        "selected_objects_only": False,
        "export_meshes": True,
        "export_shapekeys": True,
        "export_animation": animated,
        "export_armatures": True,
        "export_materials": True,
        "export_global_forward_selection": "NEGATIVE_Z",
        "export_global_up_selection": "Y",
        "convert_orientation": True,
        "meters_per_unit": 1.0,
        "only_deform_bones": False,
    }
    kwargs = {key: value for key, value in kwargs.items() if key in properties}
    bpy.ops.wm.usd_export(filepath=path, **kwargs)


def merge_animations(first_path: str, others: dict[str, str], output_path: str) -> None:
    from pxr import Sdf, Usd

    def animation_path(stage):
        for prim in stage.Traverse():
            if prim.GetTypeName() == "SkelAnimation":
                return prim.GetPath()
        raise SystemExit("导出的 USD 里没有 SkelAnimation")

    def skeleton_path(stage):
        for prim in stage.Traverse():
            if prim.GetTypeName() == "Skeleton":
                return prim.GetPath()
        raise SystemExit("导出的 USD 里没有 Skeleton")

    base_stage = Usd.Stage.Open(first_path)
    base_layer = base_stage.GetRootLayer()
    skeleton = skeleton_path(base_stage)
    base_animation = animation_path(base_stage)
    parent = base_animation.GetParentPath()

    first_tag = next(iter(others))
    first_destination = parent.AppendChild(first_tag)
    namespace_edit = Sdf.BatchNamespaceEdit()
    namespace_edit.Add(base_animation, first_destination)
    if not base_layer.Apply(namespace_edit):
        raise SystemExit(f"无法重命名动画 {base_animation} → {first_destination}")

    for tag, path in others.items():
        if tag == first_tag:
            continue
        source_stage = Usd.Stage.Open(path)
        source_layer = source_stage.GetRootLayer()
        Sdf.CopySpec(source_layer, animation_path(source_stage), base_layer, parent.AppendChild(tag))

    animation_relationship = base_stage.GetPrimAtPath(skeleton).GetRelationship("skel:animationSource")
    if animation_relationship:
        animation_relationship.SetTargets([first_destination])

    base_stage.Export(output_path)
    print(f"MERGED {output_path}")


def relativize_textures(usd_path: str) -> None:
    from pxr import Sdf, Usd

    stage = Usd.Stage.Open(usd_path)
    texture_dir = os.path.join(os.path.dirname(usd_path), "textures")
    os.makedirs(texture_dir, exist_ok=True)

    copied = 0
    for prim in stage.Traverse():
        for attribute in prim.GetAttributes():
            if attribute.GetTypeName() != Sdf.ValueTypeNames.Asset:
                continue
            asset = attribute.Get()
            if not asset or not os.path.isabs(asset.path):
                continue
            source = asset.path
            destination = os.path.join(texture_dir, os.path.basename(source))
            shutil.copyfile(source, destination)
            copied += 1
            attribute.Set(Sdf.AssetPath(f"textures/{os.path.basename(source)}"))

    stage.GetRootLayer().Save()
    print(f"TEXTURES {copied} -> {texture_dir}")


def export_actions_to_usd(armature, scene, output_path: str, temp_prefix: str = "avatar-usd-") -> None:
    """Export all eight actions and merge them into one USD."""
    if not armature.animation_data:
        raise SystemExit("骨架没有 animation_data")
    temp_dir = tempfile.mkdtemp(prefix=temp_prefix)
    exports: dict[str, str] = {}
    for tag in ACTION_NAMES:
        action = bpy.data.actions.get(tag)
        if action is None:
            raise SystemExit(f"缺少动作: {tag}")
        end_frame = int(round(action.frame_range[1]))
        armature.animation_data.action = action
        scene.frame_start = 1
        scene.frame_end = end_frame
        path = os.path.join(temp_dir, f"{tag}.usdc")
        export_usd(path, animated=True)
        print(f"BAKED {tag} frames=1-{end_frame} {path}")
        exports[tag] = path
        armature.animation_data.action = None

    first_tag = next(iter(exports))
    merge_animations(exports[first_tag], exports, output_path)
    relativize_textures(output_path)
