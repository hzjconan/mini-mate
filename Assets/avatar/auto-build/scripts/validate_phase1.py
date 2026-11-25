"""Validate the Phase 1 avatar and USDZ against the M1 asset contract.

Run:
    blender --background --factory-startup --python scripts/validate_phase1.py
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

import bpy
import numpy as np
from mathutils import Quaternion, Vector

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
CONFIG = json.loads((ROOT / "config" / "avatar.json").read_text(encoding="utf-8"))
PHASE0_BLEND = ROOT / "work" / "phase0" / "minimate_phase0.blend"
BLEND = ROOT / "work" / "phase1" / "minimate_phase1.blend"
USDZ = ROOT / "out" / "minimate_phase1.usdz"
REPORT = ROOT / "reports" / "validation-phase1.md"
AVATAR_COMMON = SCRIPT_DIR / "avatar_common.py"
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


def _skin_vertex_indices(body) -> set[int]:
    return {
        vi
        for poly in body.data.polygons
        if poly.material_index == 0
        for vi in poly.vertices
    }


def _vg_weight(vertex, group_index: int | None) -> float:
    if group_index is None:
        return 0.0
    for group in vertex.groups:
        if group.group == group_index:
            return float(group.weight)
    return 0.0


def _read_phase0_reference() -> dict:
    """Snapshot Phase 0 leg-boundary and finger-tip baselines for deterministic diffing."""
    if not PHASE0_BLEND.exists():
        raise SystemExit(f"缺少基线 {PHASE0_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(PHASE0_BLEND))
    body = bpy.data.objects.get("Body")
    if body is None:
        raise SystemExit("phase0.blend 缺少 Body")
    skin_verts = _skin_vertex_indices(body)
    mat = body.matrix_world
    vg_index = {vg.name: vg.index for vg in body.vertex_groups}

    boundary_coords: dict[int, Vector] = {}
    for vi in skin_verts:
        w = mat @ body.data.vertices[vi].co
        if abs(w.x) > 0.01 and abs(w.y) < 0.15:
            if (0.055 <= w.z <= 0.068) or (0.358 <= w.z <= 0.370):
                boundary_coords[vi] = w.copy()

    finger_ref: dict[tuple[str, str], dict] = {}
    for side in ("R", "L"):
        for finger in ("Index", "Middle", "Ring", "Little"):
            g1 = vg_index.get(f"J_Bip_{side}_{finger}1")
            g3 = vg_index.get(f"J_Bip_{side}_{finger}3")
            idx1 = [vi for vi in skin_verts if _vg_weight(body.data.vertices[vi], g1) > 0.5]
            idx3 = [vi for vi in skin_verts if _vg_weight(body.data.vertices[vi], g3) > 0.5]
            c1 = sum((mat @ body.data.vertices[vi].co for vi in idx1), Vector()) / max(1, len(idx1))
            c3 = sum((mat @ body.data.vertices[vi].co for vi in idx3), Vector()) / max(1, len(idx3))
            finger_ref[(side, finger)] = {
                "idx1": idx1,
                "idx3": idx3,
                "c1": c1,
                "c3": c3,
                "len": (c3 - c1).length,
            }
    return {"boundary_coords": boundary_coords, "finger_ref": finger_ref}


def _expected_shy_upper_arm_quat() -> Quaternion:
    text = AVATAR_COMMON.read_text(encoding="utf-8")
    match = re.search(
        r'shy_pose\s*=\s*\{.*?"J_Bip_R_UpperArm"\s*:\s*Quaternion\(\(([^)]+)\)\)',
        text,
        re.S,
    )
    if not match:
        raise SystemExit("无法从 avatar_common.py 解析 shy_pose J_Bip_R_UpperArm")
    vals = [float(x.strip()) for x in match.group(1).split(",")]
    return Quaternion(tuple(vals)).normalized()


def _hand_vertex_indices(body, skin_verts: set[int], side: str) -> list[int]:
    prefixes = (f"J_Bip_{side}_Hand", f"J_Bip_{side}_Thumb", f"J_Bip_{side}_Index", f"J_Bip_{side}_Middle", f"J_Bip_{side}_Ring", f"J_Bip_{side}_Little")
    target_groups = {vg.index for vg in body.vertex_groups if vg.name.startswith(prefixes)}
    result: list[int] = []
    for vi in skin_verts:
        v = body.data.vertices[vi]
        if any(g.group in target_groups and g.weight > 0.1 for g in v.groups):
            result.append(vi)
    return result


def _min_distance_np(a: np.ndarray, b: np.ndarray) -> float:
    # Chunked pairwise Euclidean distance to stay fast and memory-light.
    best = float("inf")
    step = 256
    for i in range(0, len(a), step):
        diff = a[i : i + step, None, :] - b[None, :, :]
        d2 = np.sum(diff * diff, axis=-1)
        cur = float(np.sqrt(np.min(d2)))
        if cur < best:
            best = cur
    return best


def main() -> None:
    if not BLEND.exists():
        raise SystemExit(f"缺少 {BLEND}")
    phase0_ref = _read_phase0_reference()
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

    # ---- Phase 1.4 deterministic geometry & action checks ----
    body = bpy.data.objects.get("Body")
    check("Body 网格存在", body is not None)
    if body is not None:
        skin_verts = _skin_vertex_indices(body)
        mat = body.matrix_world
        vg_index = {vg.name: vg.index for vg in body.vertex_groups}

        # 1. Straight calves contour + ankle/thigh boundary stability + outward sock normals
        calf_ok = True
        calf_details: list[str] = []
        for side, sign in (("L", 1.0), ("R", -1.0)):
            pts = [
                mat @ body.data.vertices[vi].co
                for vi in skin_verts
                if (mat @ body.data.vertices[vi].co).x * sign > 0.01
                and abs((mat @ body.data.vertices[vi].co).y) < 0.15
                and 0.22 <= (mat @ body.data.vertices[vi].co).z <= 0.26
            ]
            wx = max(p.x for p in pts) - min(p.x for p in pts) if pts else 9.0
            dy = max(p.y for p in pts) - min(p.y for p in pts) if pts else 9.0
            ymax = max(p.y for p in pts) if pts else 9.0
            if not (wx <= 0.082 and dy <= 0.095 and ymax <= 0.075):
                calf_ok = False
            calf_details.append(f"{side}(wx={wx:.4f},dy={dy:.4f},ymax={ymax:.4f})")
        check("Phase 1.4 直腿轮廓达标", calf_ok, " ".join(calf_details))

        max_boundary_disp = 0.0
        for vi, ref_w in phase0_ref["boundary_coords"].items():
            cur_w = mat @ body.data.vertices[vi].co
            disp = (cur_w - ref_w).length
            if disp > max_boundary_disp:
                max_boundary_disp = disp
        sock_outward_ok = True
        sock_details: list[str] = []
        for sname in ("SockL", "SockR"):
            sobj = bpy.data.objects.get(sname)
            if sobj is None or len(sobj.data.vertices) < 100:
                sock_outward_ok = False
                sock_details.append(f"{sname}=missing")
                continue
            smat = sobj.matrix_world
            srot = smat.to_3x3()
            all_verts = [smat @ v.co for v in sobj.data.vertices]
            cx = sum(p.x for p in all_verts) / len(all_verts)
            cy = sum(p.y for p in all_verts) / len(all_verts)
            inward = 0
            for poly in sobj.data.polygons:
                pc = smat @ poly.center
                pn = (srot @ poly.normal).normalized()
                radial = Vector((pc.x - cx, pc.y - cy, 0.0))
                if radial.length > 1e-5 and radial.dot(Vector((pn.x, pn.y, 0.0))) <= 0.0:
                    inward += 1
            if inward > 0:
                sock_outward_ok = False
            sock_details.append(f"{sname}(v={len(sobj.data.vertices)},inward={inward})")
        check(
            "Phase 1.4 踝/大腿衔接与袜子法线",
            max_boundary_disp < 1e-4 and sock_outward_ok,
            f"max_disp={max_boundary_disp:.6f} {' '.join(sock_details)}",
        )

        # 2. Palm thickness via PCA
        palm_thick: dict[str, float] = {}
        for side in ("L", "R"):
            h_idx = vg_index.get(f"J_Bip_{side}_Hand")
            pts = [
                mat @ body.data.vertices[vi].co
                for vi in skin_verts
                if _vg_weight(body.data.vertices[vi], h_idx) > 0.5
                and (mat @ body.data.vertices[vi].co).y > -0.045
            ]
            arr = np.array([[p.x, p.y, p.z] for p in pts], dtype=float)
            _w, vecs = np.linalg.eigh(np.cov(arr.T))
            n = vecs[:, 0]
            palm_thick[side] = float(np.ptp(arr @ n))
        sym_diff = abs(palm_thick["L"] - palm_thick["R"])
        check(
            "Phase 1.4 手掌厚度达标",
            0.029 <= palm_thick["L"] <= 0.042
            and 0.029 <= palm_thick["R"] <= 0.042
            and sym_diff < 0.002,
            f"L={palm_thick['L']:.4f} R={palm_thick['R']:.4f} diff={sym_diff:.4f}",
        )

        # 3. Rest hand natural curl direction, progression & finger length preservation
        curl_ok = True
        curl_notes: list[str] = []
        for side in ("R", "L"):
            dxs: dict[str, float] = {}
            for finger in ("Index", "Middle", "Ring", "Little"):
                ref = phase0_ref["finger_ref"][(side, finger)]
                c1_cur = sum((mat @ body.data.vertices[vi].co for vi in ref["idx1"]), Vector()) / max(1, len(ref["idx1"]))
                c3_cur = sum((mat @ body.data.vertices[vi].co for vi in ref["idx3"]), Vector()) / max(1, len(ref["idx3"]))
                dx = c3_cur.x - ref["c3"].x
                dxs[finger] = dx
                len_cur = (c3_cur - c1_cur).length
                len_ratio = abs(len_cur - ref["len"]) / max(ref["len"], 1e-6)
                dir_ok = (dx > 0.004) if side == "R" else (dx < -0.004)
                if not dir_ok or len_ratio >= 0.10:
                    curl_ok = False
                curl_notes.append(f"{side}_{finger}(dx={dx:+.4f},dL={len_ratio:.3f})")
            if not (abs(dxs["Index"]) < abs(dxs["Little"])):
                curl_ok = False
        check("Phase 1.4 静置手型自然微弯", curl_ok, " ".join(curl_notes))

        # 4 & 5. Action collision clearance (shyCover, heart) + shyCover sync with avatar_common.py
        r_hand_ids = _hand_vertex_indices(body, skin_verts, "R")
        l_hand_ids = _hand_vertex_indices(body, skin_verts, "L")
        shy_min_dist = -1.0
        heart_min_dist = -1.0
        shy_sync_deg = 999.0

        shy_action = bpy.data.actions.get("shyCover")
        if shy_action and face is not None:
            armature.animation_data.action = shy_action
            scene.frame_set(15)
            deps = bpy.context.evaluated_depsgraph_get()
            pose_q = armature.pose.bones["J_Bip_R_UpperArm"].rotation_quaternion.normalized()
            ref_q = _expected_shy_upper_arm_quat()
            shy_sync_deg = math.degrees(pose_q.rotation_difference(ref_q).angle)
            body_eval = body.evaluated_get(deps)
            face_eval = face.evaluated_get(deps)
            bm_mesh = body_eval.to_mesh()
            fm_mesh = face_eval.to_mesh()
            bmat = body_eval.matrix_world
            fmat = face_eval.matrix_world
            rh_pts = np.array([list(bmat @ bm_mesh.vertices[vi].co) for vi in r_hand_ids], dtype=float)
            f_pts = np.array([list(fmat @ v.co) for v in fm_mesh.vertices], dtype=float)
            shy_min_dist = _min_distance_np(rh_pts, f_pts)
            body_eval.to_mesh_clear()
            face_eval.to_mesh_clear()

        heart_action = bpy.data.actions.get("heart")
        if heart_action:
            armature.animation_data.action = heart_action
            scene.frame_set(15)
            deps = bpy.context.evaluated_depsgraph_get()
            body_eval = body.evaluated_get(deps)
            bm_mesh = body_eval.to_mesh()
            bmat = body_eval.matrix_world
            rh_pts = np.array([list(bmat @ bm_mesh.vertices[vi].co) for vi in r_hand_ids], dtype=float)
            lh_pts = np.array([list(bmat @ bm_mesh.vertices[vi].co) for vi in l_hand_ids], dtype=float)
            heart_min_dist = _min_distance_np(rh_pts, lh_pts)
            body_eval.to_mesh_clear()

        armature.animation_data.action = None
        scene.frame_set(1)
        check(
            "Phase 1.4 动作防穿模间隙",
            shy_min_dist >= 0.002 and heart_min_dist >= 0.015,
            f"shyCover_hand_face={shy_min_dist:.4f}m heart_hands={heart_min_dist:.4f}m",
        )
        check(
            "Phase 1.4 最新动作已同步",
            shy_sync_deg < 0.5,
            f"shyCover_R_UpperArm_diff={shy_sync_deg:.3f}deg",
        )
    else:
        check("Phase 1.4 Body 几何与动作检查", False, "缺少 Body 网格")

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

        # 6. USDZ SockWhite material contract
        from pxr import UsdShade

        sock_mat_prim = stage.GetPrimAtPath("/root/_materials/SockWhite")
        sock_mat_ok = bool(sock_mat_prim and sock_mat_prim.IsValid())
        sock_bindings: dict[str, str] = {}
        for prim in stage.Traverse():
            if prim.GetTypeName() == "Mesh" and prim.GetName() in ("SockL", "SockR"):
                bound_mat, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
                sock_bindings[prim.GetName()] = bound_mat.GetPrim().GetName() if bound_mat else "NONE"
        opacity_val = None
        metallic_val = None
        roughness_val = None
        emissive_val = None
        diffuse_val = None
        if sock_mat_ok:
            for child in sock_mat_prim.GetChildren():
                if child.GetTypeName() != "Shader":
                    continue
                shader = UsdShade.Shader(child)
                if shader.GetShaderId() != "UsdPreviewSurface":
                    continue
                opacity_in = shader.GetInput("opacity")
                metallic_in = shader.GetInput("metallic")
                roughness_in = shader.GetInput("roughness")
                emissive_in = shader.GetInput("emissiveColor")
                diffuse_in = shader.GetInput("diffuseColor")
                opacity_val = float(opacity_in.Get()) if opacity_in and opacity_in.Get() is not None else None
                metallic_val = float(metallic_in.Get()) if metallic_in and metallic_in.Get() is not None else None
                roughness_val = float(roughness_in.Get()) if roughness_in and roughness_in.Get() is not None else None
                emissive_val = tuple(float(c) for c in emissive_in.Get()) if emissive_in and emissive_in.Get() is not None else None
                diffuse_val = tuple(float(c) for c in diffuse_in.Get()) if diffuse_in and diffuse_in.Get() is not None else None
        sock_contract_ok = (
            sock_mat_ok
            and sock_bindings.get("SockL") == "SockWhite"
            and sock_bindings.get("SockR") == "SockWhite"
            and opacity_val is not None
            and abs(opacity_val - 1.0) < 1e-4
            and metallic_val is not None
            and abs(metallic_val - 0.0) < 1e-4
            and roughness_val is not None
            and roughness_val >= 0.80
            and emissive_val is not None
            and all(c >= 0.55 for c in emissive_val)
            and diffuse_val is not None
            and all(c >= 0.15 for c in diffuse_val)
        )
        check(
            "Phase 1.4 USDZ 白袜材质契约",
            sock_contract_ok,
            f"bindings={sock_bindings} opacity={opacity_val} metallic={metallic_val} roughness={roughness_val} emissive={emissive_val} diffuse={diffuse_val}",
        )
    else:
        check("USDZ 检查", False, "文件不存在")

    lines = [
        "# Phase 1.4 验证报告",
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
