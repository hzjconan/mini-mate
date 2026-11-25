"""Shared helpers for the avatar auto-build pipeline."""

from __future__ import annotations

import json
import math
import os
import shutil
import tempfile
from pathlib import Path

import bpy
from mathutils import Euler, Quaternion

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


def _remove_generated_actions(armature) -> None:
    """允许在已有 .blend 上重跑动作生成，否则会新建 `nod.001`，导出时仍取旧 `nod`。"""
    if armature.animation_data:
        armature.animation_data.action = None
    for tag in ACTION_NAMES:
        action = bpy.data.actions.get(tag)
        if action is not None:
            bpy.data.actions.remove(action)


def _local_basis_for_world_euler(armature, bone_name: str, euler) -> Quaternion:
    """把骨架空间的世界轴旋转换算成骨骼局部的 basis 四元数。

    `pose_bone.rotation_quaternion` 是相对骨骼 rest 朝向的局部旋转。直接写欧拉时
    同样的数值会因骨骼 rest 朝向不同而变成侧倾、后摆（例如头部 roll 被误当成
    lookAround）。新动作统一用骨架空间描述：X 正 = 低头/前倾，Y = 侧向，Z = 转身。
    """
    rest = armature.data.bones[bone_name].matrix_local.to_quaternion()
    return rest.inverted() @ Euler(euler, "XYZ").to_quaternion() @ rest


def make_actions(armature, fps: int = 30) -> dict[str, int]:
    """Create the eight required actions; names match ActionTag.rawValue."""
    _remove_generated_actions(armature)
    armature.animation_data_create()
    head = find_bone(armature, lambda n: n.endswith("Head"))
    neck = find_bone(armature, lambda n: n.endswith("Neck"))
    chest = find_bone(armature, lambda n: n.endswith("Chest"))
    spine = find_bone(armature, lambda n: n.endswith("Spine") or n.endswith("Chest"))
    hips = find_bone(armature, lambda n: n.endswith("Hips"))
    root = find_bone(armature, lambda n: n == "Root")
    right_arm = find_bone(armature, lambda n: "R_UpperArm" in n or "UpperArm.R" in n)
    right_lower_arm = find_bone(armature, lambda n: "R_LowerArm" in n or "LowerArm.R" in n)
    right_shoulder = find_bone(armature, lambda n: "R_Shoulder" in n or "Shoulder.R" in n)
    right_hand = find_bone(armature, lambda n: "R_Hand" in n or "Hand.R" in n)
    left_arm = find_bone(armature, lambda n: "L_UpperArm" in n or "UpperArm.L" in n)
    right_fingers = [
        f"J_Bip_R_{prefix}{i}"
        for prefix in ("Index", "Middle", "Ring", "Little")
        for i in (1, 2, 3)
        if f"J_Bip_R_{prefix}{i}" in armature.pose.bones
    ]
    right_thumb = [
        f"J_Bip_R_Thumb{i}" for i in (1, 2, 3) if f"J_Bip_R_Thumb{i}" in armature.pose.bones
    ]
    print(
        f"ACTION_BONES head={head} neck={neck} chest={chest} spine={spine} "
        f"hips={hips} root={root} right={right_arm} lower={right_lower_arm} "
        f"shoulder={right_shoulder} hand={right_hand} fingers={len(right_fingers)} "
        f"thumb={len(right_thumb)} left={left_arm}"
    )

    # 手腕绕自身 Y 轴（骨骼长轴）扭转，把掌心从朝侧面转向前方镜头。
    # 正向 +75°：右手掌心朝镜头时拇指应在内侧（靠近头）；此前用 -100° 转到
    # 了手背朝镜头，拇指跑到外侧——用户一眼看出的就是这个。
    # 四元数直接作为局部 basis 写入，不再经世界轴换算。
    hand_rest = Quaternion((0, 1, 0), 0.0)
    hand_half = Quaternion((0, 1, 0), math.radians(37.5))
    hand_wave = Quaternion((0, 1, 0), math.radians(75))

    def finger_curl(finger_degrees: float, thumb_degrees: float) -> dict:
        """手指/拇指绕局部 X 轴负向弯曲；负值才是朝手心。"""
        fingerq = Quaternion((1, 0, 0), math.radians(finger_degrees))
        thumbq = Quaternion((1, 0, 0), math.radians(thumb_degrees))
        pose = {name: fingerq for name in right_fingers}
        pose.update({name: thumbq for name in right_thumb})
        return pose

    # 双手捧心：双手在胸前摊开、掌心向上，手指轻收，爱心特效从手心上方出现。
    # 手小、袖子大，强行让手指围成心形在 App 尺寸下读不出来；改为自然捧心，
    # 含义由特效承担。手臂四元数由 IK 把手放到胸前并翻成掌心向上后烘焙。
    heart_pose = {
        "J_Bip_R_UpperArm": Quaternion((0.744821, 0.058250, -0.257089, 0.612988)),
        "J_Bip_R_LowerArm": Quaternion((0.989466, 0.023566, 0.0, 0.142836)),
        "J_Bip_R_Hand": Quaternion((0.461017, 0.142033, 0.833104, 0.270606)),
        "J_Bip_L_UpperArm": Quaternion((0.746036, 0.059396, 0.256847, -0.611501)),
        "J_Bip_L_LowerArm": Quaternion((0.989068, 0.024002, 0.0, -0.145491)),
        "J_Bip_L_Hand": Quaternion((0.460666, 0.142420, -0.833550, -0.269624)),
    }
    # 拇指向上并向手心内收（右拇指 Y+ / Z-，左拇指镜像），看起来是拇指
    # 自然扣在掌心侧，而不是一根向外张开的长手指。
    thumb_pose = {
        "R": (
            Quaternion((0, 1, 0), math.radians(12))
            @ Quaternion((0, 0, 1), math.radians(-20)),
            Quaternion((0, 1, 0), math.radians(6))
            @ Quaternion((0, 0, 1), math.radians(-10)),
            Quaternion((0, 0, 1), math.radians(-6)),
        ),
        "L": (
            Quaternion((0, 1, 0), math.radians(-12))
            @ Quaternion((0, 0, 1), math.radians(20)),
            Quaternion((0, 1, 0), math.radians(-6))
            @ Quaternion((0, 0, 1), math.radians(10)),
            Quaternion((0, 0, 1), math.radians(6)),
        ),
    }
    for _side in ("R", "L"):
        for _prefix in ("Index", "Middle", "Ring", "Little"):
            for _index in (1, 2, 3):
                heart_pose[f"J_Bip_{_side}_{_prefix}{_index}"] = Quaternion(
                    (1, 0, 0), math.radians(-8)
                )
        for _index in (1, 2, 3):
            heart_pose[f"J_Bip_{_side}_Thumb{_index}"] = thumb_pose[_side][_index - 1]
    heart_pose_rest = {name: Quaternion((1, 0, 0), 0.0) for name in heart_pose}

    # 害羞遮嘴（经典手势）：手背朝镜头、手指朝上，掌侧轻贴嘴前；手腕落在
    # 下巴下方，袖口远离嘴。手臂/手腕四元数由 IK + 世界轴滚转烘焙。
    shy_pose = {
        "J_Bip_R_UpperArm": Quaternion((0.835787, 0.080820, -0.389347, 0.378599)),
        "J_Bip_R_LowerArm": Quaternion((0.678676, 0.119557, 0.0, 0.724642)),
        "J_Bip_R_Hand": Quaternion((0.771843, 0.065978, 0.340877, 0.532643)),
    }
    # 五指并拢、略微收拢（局部 X 负向朝掌心），指尖朝上。
    for _prefix in ("Index", "Middle", "Ring", "Little"):
        for _index in (1, 2, 3):
            shy_pose[f"J_Bip_R_{_prefix}{_index}"] = Quaternion(
                (1, 0, 0), math.radians(-5)
            )
    shy_pose_rest = {name: Quaternion((1, 0, 0), 0.0) for name in shy_pose}

    # 世界轴语义动作：X 正 = 低头/前倾（角色面向 -Y），Y = 侧向，Z = 转身。
    # 每修好一个动作就从局部轴 specs 迁到这里，便于逐个真机确认。
    world_specs = {
        "nod": [
            (0.0, {head: (0.0, 0.0, 0.0), neck: (0.0, 0.0, 0.0)}),
            (0.22, {head: (0.34, 0.0, 0.0), neck: (0.10, 0.0, 0.0)}),
            (0.40, {head: (0.38, 0.0, 0.0), neck: (0.12, 0.0, 0.0)}),
            (0.58, {head: (0.02, 0.0, 0.0), neck: (0.01, 0.0, 0.0)}),
            (0.76, {head: (0.22, 0.0, 0.0), neck: (0.07, 0.0, 0.0)}),
            (0.94, {head: (0.0, 0.0, 0.0), neck: (0.0, 0.0, 0.0)}),
            (1.0, {head: (0.0, 0.0, 0.0), neck: (0.0, 0.0, 0.0)}),
        ],
        # 右手举起挥手：肩先抬 0.25，上臂再抬 1.10，肘部在 0.90–1.45 之间摆动；
        # 手腕同时绕自身长轴转 -100°，让掌心朝向镜头。
        # 世界 Y 轴正方向把右臂向外上方抬；肘部同轴正方向把前臂折向头部。
        "wave": [
            (
                0.0,
                {
                    right_shoulder: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    right_lower_arm: (0, 0, 0),
                    right_hand: hand_rest,
                    head: (0, 0, 0),
                    **finger_curl(0, 0),
                },
            ),
            (
                0.20,
                {
                    right_shoulder: (0, 0.08, 0),
                    right_arm: (0, 0.35, 0),
                    right_lower_arm: (0, 0.35, 0),
                    right_hand: hand_half,
                    head: (0, -0.04, 0),
                    **finger_curl(-6, -5),
                },
            ),
            (
                0.38,
                {
                    right_shoulder: (0, 0.25, 0),
                    right_arm: (0, 1.10, 0),
                    right_lower_arm: (0, 1.30, 0),
                    right_hand: hand_wave,
                    head: (0, -0.10, 0),
                    **finger_curl(-12, -10),
                },
            ),
            (
                0.58,
                {
                    right_shoulder: (0, 0.25, 0),
                    right_arm: (0, 1.10, 0),
                    right_lower_arm: (0, 0.90, 0),
                    right_hand: hand_wave,
                    head: (0, -0.10, 0),
                    **finger_curl(-12, -10),
                },
            ),
            (
                0.78,
                {
                    right_shoulder: (0, 0.25, 0),
                    right_arm: (0, 1.10, 0),
                    right_lower_arm: (0, 1.45, 0),
                    right_hand: hand_wave,
                    head: (0, -0.10, 0),
                    **finger_curl(-12, -10),
                },
            ),
            (
                0.98,
                {
                    right_shoulder: (0, 0.25, 0),
                    right_arm: (0, 1.10, 0),
                    right_lower_arm: (0, 0.90, 0),
                    right_hand: hand_wave,
                    head: (0, -0.10, 0),
                    **finger_curl(-12, -10),
                },
            ),
            (
                1.14,
                {
                    right_shoulder: (0, 0.10, 0),
                    right_arm: (0, 0.40, 0),
                    right_lower_arm: (0, 0.40, 0),
                    right_hand: hand_half,
                    head: (0, -0.04, 0),
                    **finger_curl(-6, -5),
                },
            ),
            (
                1.28,
                {
                    right_shoulder: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    right_lower_arm: (0, 0, 0),
                    right_hand: hand_rest,
                    head: (0, 0, 0),
                    **finger_curl(0, 0),
                },
            ),
            (
                1.4,
                {
                    right_shoulder: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    right_lower_arm: (0, 0, 0),
                    right_hand: hand_rest,
                    head: (0, 0, 0),
                    **finger_curl(0, 0),
                },
            ),
        ],
        # 原地转身：Root 绕世界 Z 轴（竖直轴）转 360°。Root 在脚底中心，
        # 身体保持直立，不再像旧版绕 Hips 的倾斜局部 Z 轴侧翻。
        # 起步先反向蓄力，胸腔略滞后，手臂稍微张开增加动感。
        "spin": [
            (0.0, {root: (0, 0, 0), chest: (0, 0, 0), right_arm: (0, 0, 0), left_arm: (0, 0, 0)}),
            (0.18, {root: (0, 0, -0.25), chest: (0, 0, 0.12), right_arm: (0, 0.08, 0), left_arm: (0, -0.08, 0)}),
            (0.34, {root: (0, 0, 0.35), chest: (0, 0, -0.06), right_arm: (0, 0.22, 0), left_arm: (0, -0.22, 0)}),
            (0.54, {root: (0, 0, 1.85), chest: (0, 0, -0.08), right_arm: (0, 0.30, 0), left_arm: (0, -0.30, 0)}),
            (0.74, {root: (0, 0, 3.35), chest: (0, 0, -0.08), right_arm: (0, 0.30, 0), left_arm: (0, -0.30, 0)}),
            (0.94, {root: (0, 0, 4.85), chest: (0, 0, -0.08), right_arm: (0, 0.30, 0), left_arm: (0, -0.30, 0)}),
            (1.14, {root: (0, 0, 6.05), chest: (0, 0, -0.03), right_arm: (0, 0.18, 0), left_arm: (0, -0.18, 0)}),
            (1.30, {root: (0, 0, 2 * math.pi), chest: (0, 0, 0), right_arm: (0, 0.05, 0), left_arm: (0, -0.05, 0)}),
            (1.45, {root: (0, 0, 2 * math.pi), chest: (0, 0, 0), right_arm: (0, 0, 0), left_arm: (0, 0, 0)}),
            (1.6, {root: (0, 0, 2 * math.pi), chest: (0, 0, 0), right_arm: (0, 0, 0), left_arm: (0, 0, 0)}),
        ],
        # 双手比心：双手在胸前合拢，食指在上、拇指在下围成心形。
        "heart": [
            (0.0, {head: (0, 0, 0), **heart_pose_rest}),
            (0.30, {head: (0.06, 0, 0), **heart_pose}),
            (0.90, {head: (0.06, 0, 0), **heart_pose}),
            (1.20, {head: (0, 0, 0), **heart_pose_rest}),
            (1.4, {head: (0, 0, 0), **heart_pose_rest}),
        ],
        # 害羞遮脸：双手抬到嘴前，掌心朝向脸，头略低并侧倾。
        "shyCover": [
            (0.0, {head: (0, 0, 0), **shy_pose_rest}),
            (0.30, {head: (0.15, -0.04, 0), **shy_pose}),
            (0.55, {head: (0.15, -0.04, 0), **shy_pose}),
            (0.90, {head: (0.15, -0.04, 0), **shy_pose}),
            (1.15, {head: (0, 0, 0), **shy_pose_rest}),
            (1.3, {head: (0, 0, 0), **shy_pose_rest}),
            (1.4, {head: (0, 0, 0), **shy_pose_rest}),
        ],
        # 收身后仰：先轻微前倾做预备，再由脊柱和胸向后带；颈/头反向点头，
        # 保持视线向前（避免整块上身像板子一样倒）；双臂轻微前摆配重，
        # 最后回正并留一拍。世界轴语义：X 正 = 前倾/低头，Z = 转头。
        "leanBack": [
            (
                0.0,
                {
                    spine: (0, 0, 0),
                    chest: (0, 0, 0),
                    neck: (0, 0, 0),
                    head: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    left_arm: (0, 0, 0),
                },
            ),
            (
                0.28,
                {
                    spine: (0.03, 0, 0),
                    chest: (0.015, 0, 0),
                    neck: (0.0, 0, 0),
                    head: (0.01, 0, 0),
                    right_arm: (0.03, 0, 0),
                    left_arm: (0.03, 0, 0),
                },
            ),
            (
                0.62,
                {
                    spine: (-0.18, 0, 0),
                    chest: (-0.12, 0, 0),
                    neck: (0.10, 0, 0),
                    head: (0.09, 0, 0.06),
                    right_arm: (-0.08, 0, 0),
                    left_arm: (-0.08, 0, 0),
                },
            ),
            (
                0.88,
                {
                    spine: (-0.14, 0, 0),
                    chest: (-0.085, 0, 0),
                    neck: (0.08, 0, 0),
                    head: (0.07, 0, 0.04),
                    right_arm: (-0.05, 0, 0),
                    left_arm: (-0.05, 0, 0),
                },
            ),
            (
                1.18,
                {
                    spine: (0, 0, 0),
                    chest: (0, 0, 0),
                    neck: (0, 0, 0),
                    head: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    left_arm: (0, 0, 0),
                },
            ),
            (
                1.32,
                {
                    spine: (0, 0, 0),
                    chest: (0, 0, 0),
                    neck: (0, 0, 0),
                    head: (0, 0, 0),
                    right_arm: (0, 0, 0),
                    left_arm: (0, 0, 0),
                },
            ),
        ],
        # 左右张望：用世界 Z 轴转头（局部 Z 会变成歪头），颈部/胸部分担一部分；
        # 两侧各停一拍再回中；头略微下沉并向看的方向侧倾，避免像快速摇头。
        "lookAround": [
            (0.0, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
            (0.32, {chest: (0, 0, 0.03), neck: (0, 0, 0.12), head: (0.03, 0.03, 0.26)}),
            (0.50, {chest: (0, 0, 0.03), neck: (0, 0, 0.12), head: (0.03, 0.03, 0.26)}),
            (0.68, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
            (0.86, {chest: (0, 0, -0.03), neck: (0, 0, -0.12), head: (0.03, -0.03, -0.26)}),
            (1.04, {chest: (0, 0, -0.03), neck: (0, 0, -0.12), head: (0.03, -0.03, -0.26)}),
            (1.30, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
            (1.45, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
        ],
        # 察觉/注意到：快速向一侧转头并略微抬头，颈和胸口轻微参与；
        # 保持一短拍后回正。世界轴语义：Z 正 = 向角色左侧转头，X 负 = 抬头。
        "notice": [
            (0.0, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
            (0.22, {chest: (0, 0, 0.02), neck: (-0.02, 0, 0.10), head: (-0.06, 0.03, 0.20)}),
            (0.40, {chest: (0, 0, 0.02), neck: (-0.02, 0, 0.09), head: (-0.05, 0.03, 0.19)}),
            (0.64, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
            (0.80, {chest: (0, 0, 0), neck: (0, 0, 0), head: (0, 0, 0)}),
        ],
    }

    ranges: dict[str, int] = {}
    for tag in ACTION_NAMES:
        keys = world_specs.get(tag)
        if not keys:
            raise SystemExit(f"动作 {tag} 没有姿态定义")
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
            for bone_name, rotation in poses.items():
                if bone_name is None:
                    continue
                bone = armature.pose.bones[bone_name]
                if isinstance(rotation, Quaternion):
                    # 直接给局部 basis（例如手腕绕自身长轴扭转）。
                    bone.rotation_quaternion = rotation
                else:
                    bone.rotation_quaternion = _local_basis_for_world_euler(
                        armature, bone_name, rotation
                    )
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


TIMELINE_NAME = "actions"
ANIMATION_GAP_FRAMES = 2


def _single_prim(stage, type_name: str):
    prims = [prim for prim in stage.Traverse() if prim.GetTypeName() == type_name]
    if len(prims) != 1:
        raise SystemExit(f"期望恰好一个 {type_name}，实际 {len(prims)} 个")
    return prims[0]


def _quat_dot(a, b) -> float:
    ai, bi = a.GetImaginary(), b.GetImaginary()
    return a.GetReal() * b.GetReal() + ai[0] * bi[0] + ai[1] * bi[1] + ai[2] * bi[2]


def _quat_angle(a, b) -> float:
    """两个四元数表示的旋转之间的夹角（忽略 q/-q 符号）。"""
    return 2.0 * math.acos(min(1.0, abs(_quat_dot(a, b))))


def _negate_quat(q):
    from pxr import Gf

    return Gf.Quatf(-q.GetReal(), -q.GetImaginary())


def _read_track(stage, tag: str) -> dict:
    from pxr import UsdSkel

    prim = _single_prim(stage, "SkelAnimation")
    joints = tuple(UsdSkel.Animation(prim).GetJointsAttr().Get())
    rotations = prim.GetAttribute("rotations")
    sample_times = [int(round(t)) for t in rotations.GetTimeSamples()]
    if not sample_times:
        raise SystemExit(f"{tag} 没有旋转采样")
    # Blender 的 USD 导出会省略完全静止的中间帧（例如比心的 hold），
    # 这里把缺失帧按前一个采样补齐；补之前确认缺口两端确实一致，
    # 避免把真正的丢帧悄悄糊过去。
    time_set = set(sample_times)
    times = list(range(sample_times[0], sample_times[-1] + 1))
    frames = []
    previous = None
    previous_time = None
    for frame in times:
        if frame in time_set:
            value = rotations.Get(frame)
            if previous_time is not None and frame > previous_time + 1:
                gap_angle = max(
                    _quat_angle(previous[i], value[i]) for i in range(len(value))
                )
                if gap_angle > math.radians(1):
                    raise SystemExit(
                        f"{tag} 旋转采样在 {previous_time}-{frame} 之间丢失"
                    )
            previous = value
            previous_time = frame
        if previous is None:
            raise SystemExit(f"{tag} 旋转采样起点异常")
        frames.append(previous)
    for frame in frames:
        if len(frame) != len(joints):
            raise SystemExit(f"{tag} 旋转采样与 joints 数量不一致")

    max_deviation = max(_quat_angle(frames[0][i], frame[i]) for frame in frames for i in range(len(joints)))
    end_deviation = max(_quat_angle(frames[0][i], frames[-1][i]) for i in range(len(joints)))
    if max_deviation < math.radians(5):
        raise SystemExit(f"{tag} 几乎没有动作（最大偏差 {math.degrees(max_deviation):.1f}°）")
    if end_deviation > math.radians(1):
        raise SystemExit(f"{tag} 末帧未回到静置姿态（偏差 {math.degrees(end_deviation):.1f}°）")

    # 临时 stage 会在函数返回后回收，属性代理随即失效；这里立即把默认值与采样取出来。
    extras = {}
    for name in ("translations", "scales"):
        attr = prim.GetAttribute(name)
        if attr is None:
            extras[name] = None
            continue
        sample_times = [int(round(t)) for t in attr.GetTimeSamples()]
        extras[name] = {
            "default": attr.Get(),
            "times": sample_times or None,
            "values": [attr.Get(t) for t in sample_times] if sample_times else None,
        }

    return {
        "joints": joints,
        "times": times,
        "rotations": frames,
        "extras": extras,
    }


def _merge_attr_frames(tracks: dict, layout: dict, name: str, gap_frames: int):
    """把每个动作的某个数组属性拼成逐帧稠密的时间线；整条时间线都没有采样时返回 None。"""
    attrs = [track["extras"][name] for track in tracks.values() if track["extras"][name] is not None]
    if not any(data["times"] for data in attrs):
        return None
    fallback = attrs[0]["default"]

    merged = {}
    previous = None
    for tag in ACTION_NAMES:
        track = tracks[tag]
        data = track["extras"][name]
        start, end = layout[tag]
        if data is not None and data["times"]:
            values = data["values"]
        else:
            values = [data["default"] if data is not None else fallback] * len(track["times"])
        for offset, value in enumerate(values):
            merged[start + offset] = value
            previous = value
        if tag != ACTION_NAMES[-1]:
            for gap in range(1, gap_frames + 1):
                merged[end + gap] = previous
    return merged


def _verify_timeline(path: str, layout: dict, total_frames: int) -> None:
    from pxr import Usd, UsdSkel

    stage = Usd.Stage.Open(path)
    animation = _single_prim(stage, "SkelAnimation")
    skeleton = _single_prim(stage, "Skeleton")
    if animation.GetName() != TIMELINE_NAME:
        raise SystemExit(f"时间线名称应为 {TIMELINE_NAME}，实际 {animation.GetName()}")
    rotations = animation.GetAttribute("rotations")
    times = [int(round(t)) for t in rotations.GetTimeSamples()]
    if times != list(range(1, total_frames + 1)):
        raise SystemExit(f"时间线采样应为 1..{total_frames}，实际 {times[:3]}…{times[-3:]}")
    targets = skeleton.GetRelationship("skel:animationSource").GetTargets()
    if targets != [animation.GetPath()]:
        raise SystemExit(f"animationSource 未绑定时间线：{targets}")
    blend_weights = animation.GetAttribute("blendShapeWeights")
    if blend_weights is not None and blend_weights.GetTimeSamples():
        raise SystemExit("时间线仍包含 blendShapeWeights 采样")
    if int(round(stage.GetEndTimeCode())) != total_frames:
        raise SystemExit(f"endTimeCode 应为 {total_frames}，实际 {stage.GetEndTimeCode()}")
    joints = list(UsdSkel.Animation(animation).GetJointsAttr().Get())
    for tag, (start_frame, end_frame) in layout.items():
        if start_frame < 1 or end_frame > total_frames or end_frame <= start_frame:
            raise SystemExit(f"{tag} 片段区间非法：{start_frame}-{end_frame}")
        first = rotations.Get(start_frame)
        last = rotations.Get(end_frame)
        if len(first) != len(joints) or len(last) != len(joints):
            raise SystemExit(f"{tag} 片段采样与 joints 数量不一致")


def build_animation_timeline(exports: dict[str, str], output_path: str, gap_frames: int = ANIMATION_GAP_FRAMES) -> None:
    """把 8 个动作拼成一条 SkelAnimation 时间线，并输出 tag → 帧区间清单。

    RealityKit 只导入被 `skel:animationSource` 绑定的那一条 SkelAnimation，
    因此所有动作必须共享一条时间线；运行时按清单裁剪出独立片段。
    """
    from pxr import Sdf, Usd, Vt

    manifest_path = Path(output_path).with_name(Path(output_path).stem + ".actions.json")
    manifest_path.unlink(missing_ok=True)

    base_stage = Usd.Stage.Open(exports[ACTION_NAMES[0]])
    base_layer = base_stage.GetRootLayer()
    skeleton = _single_prim(base_stage, "Skeleton")
    base_animation = _single_prim(base_stage, "SkelAnimation")
    parent = base_animation.GetPath().GetParentPath()

    tracks = {tag: _read_track(Usd.Stage.Open(exports[tag]), tag) for tag in ACTION_NAMES}
    joints = tracks[ACTION_NAMES[0]]["joints"]
    for tag, track in tracks.items():
        if track["joints"] != joints:
            raise SystemExit(f"{tag} 的 joints 顺序与 {ACTION_NAMES[0]} 不一致")

    layout: dict[str, tuple[int, int]] = {}
    cursor = 1
    for tag in ACTION_NAMES:
        count = len(tracks[tag]["times"])
        layout[tag] = (cursor, cursor + count - 1)
        cursor += count + gap_frames
    total_frames = layout[ACTION_NAMES[-1]][1]

    # 逐帧拼接旋转；逐关节做符号连续化，抵消导出按 w≥0 归一化造成的半球翻转。
    merged_rotations = {}
    previous = None
    for tag in ACTION_NAMES:
        start, end = layout[tag]
        for offset, frame in enumerate(tracks[tag]["rotations"]):
            values = list(frame)
            if previous is not None:
                values = [
                    _negate_quat(value) if _quat_dot(previous[i], value) < 0 else value
                    for i, value in enumerate(values)
                ]
            merged_rotations[start + offset] = Vt.QuatfArray(values)
            previous = merged_rotations[start + offset]
        if tag != ACTION_NAMES[-1]:
            hold = merged_rotations[end]
            for gap in range(1, gap_frames + 1):
                merged_rotations[end + gap] = Vt.QuatfArray(list(hold))
            previous = merged_rotations[end + gap_frames]

    namespace_edit = Sdf.BatchNamespaceEdit()
    timeline_path = parent.AppendChild(TIMELINE_NAME)
    namespace_edit.Add(base_animation.GetPath(), timeline_path)
    if not base_layer.Apply(namespace_edit):
        raise SystemExit(f"无法重命名动画 {base_animation.GetPath()} → {timeline_path}")

    timeline = base_stage.GetPrimAtPath(timeline_path)
    for name in ("blendShapes", "blendShapeWeights"):
        if timeline.HasProperty(name):
            timeline.RemoveProperty(name)

    rotations = timeline.GetAttribute("rotations")
    default_rotation = rotations.Get()
    rotations.Clear()
    if default_rotation is not None:
        rotations.Set(default_rotation)
    rotations.SetMetadata("interpolation", "linear")
    for frame in range(1, total_frames + 1):
        rotations.Set(merged_rotations[frame], time=frame)

    for name in ("translations", "scales"):
        merged = _merge_attr_frames(tracks, layout, name, gap_frames)
        if merged is None:
            continue
        attr = timeline.GetAttribute(name)
        default = attr.Get()
        attr.Clear()
        if default is not None:
            attr.Set(default)
        attr.SetMetadata("interpolation", "linear")
        for frame in range(1, total_frames + 1):
            attr.Set(merged[frame], time=frame)

    base_stage.SetStartTimeCode(1)
    base_stage.SetEndTimeCode(total_frames)
    skeleton.GetRelationship("skel:animationSource").SetTargets([timeline_path])
    base_stage.Export(output_path)
    _verify_timeline(output_path, layout, total_frames)

    fps = base_stage.GetTimeCodesPerSecond()
    if fps <= 0:
        raise SystemExit(f"非法 timeCodesPerSecond：{fps}")
    manifest = {
        "version": 1,
        "fps": int(fps) if float(fps).is_integer() else fps,
        "animation": TIMELINE_NAME,
        "totalFrames": total_frames,
        "clips": {
            tag: {"startFrame": layout[tag][0], "endFrame": layout[tag][1]}
            for tag in ACTION_NAMES
        },
    }
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"TIMELINE {output_path} frames=1-{total_frames} manifest={manifest_path}")


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

    build_animation_timeline(exports, output_path)
    relativize_textures(output_path)
