"""Validate the Phase 1 avatar and USDZ against the M1 asset contract.

Run:
    blender --background --factory-startup --python scripts/validate_phase1.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import bpy

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
CONFIG = json.loads((ROOT / "config" / "avatar.json").read_text(encoding="utf-8"))
BLEND = ROOT / "work" / "phase1" / "minimate_phase1.blend"
USDZ = ROOT / "out" / "minimate_phase1.usdz"
REPORT = ROOT / "reports" / "validation-phase1.md"
ARKIT_SWIFT = ROOT.parent.parent.parent / "Packages" / "MiniMateKit" / "Sources" / "MMAvatar" / "BlendShapeIndex.swift"
ACTION_NAMES = ("nod", "wave", "spin", "heart", "shyCover", "leanBack", "lookAround", "notice")

failures: list[str] = []
checks: list[tuple[str, bool, str]] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    checks.append((name, condition, detail))
    if not condition:
        failures.append(f"{name}: {detail}")


def arkit_names() -> list[str]:
    text = ARKIT_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"arkitNames:\s*\[String\]\s*=\s*\[(.*?)\]", text, re.S)
    if not match:
        raise SystemExit("无法解析 BlendShapeIndex.swift")
    return re.findall(r'"([^"]+)"', match.group(1))


def triangle_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def find_bone(armature, suffix: str) -> bool:
    return any(bone.name.endswith(suffix) for bone in armature.data.bones)


def main() -> None:
    if not BLEND.exists():
        raise SystemExit(f"缺少 {BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    scene = bpy.context.scene
    expected = arkit_names()
    face = bpy.data.objects.get("Face")
    armature = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]

    check("Face 网格存在", face is not None)
    if face and face.data.shape_keys:
        available = {key.name for key in face.data.shape_keys.key_blocks if key.name != "Basis"}
        missing = [name for name in expected if name not in available]
        check("ARKit 52 名称", not missing, f"missing={missing}")
        check("Face 形态键目标数", len(available) == 124, f"targets={len(available)}")
    else:
        check("Face 形态键", False, "没有形态键")

    actions = {action.name for action in bpy.data.actions}
    missing_actions = [name for name in ACTION_NAMES if name not in actions]
    check("8 个动作", not missing_actions, f"missing={missing_actions}")

    check("Head 骨骼", find_bone(armature, "Head"))
    check("Neck 骨骼", find_bone(armature, "Neck"))

    triangles = sum(triangle_count(obj) for obj in meshes)
    check("三角面 < 50k", triangles < int(CONFIG["validation"]["maxTriangles"]), f"triangles={triangles}")

    too_large = [
        image.name
        for image in bpy.data.images
        if image.size[0] > 2048 or image.size[1] > 2048
    ]
    check("贴图 ≤ 2048²", not too_large, f"too_large={too_large}")

    hoodie_parts = (
        "HoodieSleeveL",
        "HoodieSleeveR",
        "HoodieCuffL",
        "HoodieCuffR",
        "HoodieHemExtension",
        "HoodieHemBand",
        "HoodiePocket",
        "HoodieCollar",
        "HoodieHood",
        "DrawstringL",
        "DrawstringR",
        "SockL",
        "SockR",
        "ShortsHemL",
        "ShortsHemR",
        "NecklineTrimL",
        "NecklineTrimR",
        "EarHeadband",
        "EarHeadbandSideL",
        "EarHeadbandSideR",
    )
    missing_parts = [name for name in hoodie_parts if bpy.data.objects.get(name) is None]
    check("Phase 1.2 服装部件", not missing_parts, f"missing={missing_parts}")

    usdz_ok = USDZ.exists()
    check("USDZ 存在", usdz_ok, str(USDZ))
    if usdz_ok:
        from pxr import Usd, UsdSkel

        manifest_path = USDZ.with_name(USDZ.stem + ".actions.json")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else None
        check("动作清单存在", manifest is not None, str(manifest_path))
        if manifest is not None:
            check(
                "清单 8 个片段",
                manifest.get("version") == 1
                and set(manifest.get("clips", {})) == set(ACTION_NAMES),
                f"clips={sorted(manifest.get('clips', {}))}",
            )

        stage = Usd.Stage.Open(str(USDZ))
        animations = []
        animation_source: list = []
        blend_shape_names: set[str] = set()
        skeleton_names: set[str] = set()
        mesh_names: set[str] = set()
        for prim in stage.Traverse():
            if prim.GetTypeName() == "SkelAnimation":
                animations.append(prim)
            if prim.GetTypeName() == "Skeleton":
                skeleton_names.add(prim.GetName())
                animation_source = prim.GetRelationship("skel:animationSource").GetTargets()
            if prim.GetTypeName() == "Mesh":
                mesh_names.add(prim.GetName())
                api = UsdSkel.BindingAPI(prim)
                targets = api.GetBlendShapeTargetsRel()
                for target_path in targets.GetTargets():
                    target = stage.GetPrimAtPath(target_path)
                    if target:
                        blend_shape_names.add(target.GetName())

        timeline = animations[0] if len(animations) == 1 else None
        check(
            "USDZ 单条动作时间线",
            timeline is not None and timeline.GetName() == "actions",
            f"animations={[prim.GetName() for prim in animations]}",
        )
        check(
            "USDZ 动作已绑定",
            timeline is not None and animation_source == [timeline.GetPath()],
            f"animationSource={animation_source}",
        )

        if timeline is not None:
            rotations = timeline.GetAttribute("rotations")
            times = [int(round(t)) for t in rotations.GetTimeSamples()]
            total_frames = int(manifest["totalFrames"]) if manifest else 0
            check(
                "时间线逐帧连续",
                bool(times)
                and times[0] == 1
                and times[-1] == total_frames
                and times == list(range(1, total_frames + 1)),
                f"samples={len(times)} range={times[:1]}..{times[-1:]} totalFrames={total_frames}",
            )
            check(
                "时间码与清单一致",
                manifest is not None
                and round(stage.GetTimeCodesPerSecond()) == round(float(manifest["fps"]))
                and int(round(stage.GetEndTimeCode())) == total_frames,
                f"fps={stage.GetTimeCodesPerSecond()} end={stage.GetEndTimeCode()}",
            )
            blend_weights = timeline.GetAttribute("blendShapeWeights")
            check(
                "时间线不含形态键动画",
                blend_weights is None or not blend_weights.GetTimeSamples(),
            )
            if manifest:
                invalid = [
                    tag
                    for tag, clip in manifest["clips"].items()
                    if clip["startFrame"] < 1
                    or clip["endFrame"] <= clip["startFrame"]
                    or clip["endFrame"] > total_frames
                ]
                check("片段区间合法", not invalid, f"invalid={invalid}")

        check("upAxis=Y", stage.GetMetadata("upAxis") == "Y", str(stage.GetMetadata("upAxis")))
        check(
            "metersPerUnit=1",
            abs(float(stage.GetMetadata("metersPerUnit")) - 1.0) < 1e-6,
            str(stage.GetMetadata("metersPerUnit")),
        )
        missing_usdz = [name for name in expected if name not in blend_shape_names]
        check("USDZ ARKit 52 名称", not missing_usdz, f"missing={missing_usdz}")
        check("USDZ 骨架", bool(skeleton_names), f"skeletons={sorted(skeleton_names)}")
        check("USDZ 可打开", True)
        check(
            "USDZ 含连帽衫网格",
            any(name.startswith("HoodieSleeve") for name in mesh_names)
            and any(name.startswith("HoodieHood") for name in mesh_names),
            f"hood_meshes={[n for n in sorted(mesh_names) if n.startswith('Hoodie')][:8]}",
        )
    else:
        check("USDZ 检查", False, "文件不存在")

    lines = [
        "# Phase 1.2 验证报告",
        "",
        f"- 模型：`{BLEND}`",
        f"- USDZ：`{USDZ}`",
        f"- 结果：{'通过' if not failures else '失败'}",
        "",
        "| 检查 | 结果 | 详情 |",
        "|---|---|---|",
    ]
    for name, ok, detail in checks:
        lines.append(f"| {name} | {'✅' if ok else '❌'} | {detail} |")
    lines += ["", "## 失败项", ""]
    lines += [f"- {item}" for item in failures] if failures else ["- 无"]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"VALIDATION_REPORT {REPORT}")
    if failures:
        print("VALIDATION_FAILED")
        for item in failures:
            print(f"FAILED {item}")
        raise SystemExit(1)
    print(f"VALIDATION_OK triangles={triangles}")


main()
