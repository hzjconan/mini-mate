"""Export the Phase 1 .blend to a USDZ candidate.

Run:
    blender --background --factory-startup --python scripts/export_phase1.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

import bpy

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import avatar_common as ac  # noqa: E402

ROOT = SCRIPT_DIR.parent
BLEND = ROOT / "work" / "phase1" / "minimate_phase1.blend"
OUT_DIR = ROOT / "out"
USDC = OUT_DIR / "minimate_phase1.usdc"
USDZ = OUT_DIR / "minimate_phase1.usdz"


def fix_preview_surface() -> None:
    """MToon's compatible Principled node defaults to metallic=1; fix for USD."""
    for material in bpy.data.materials:
        if not material.use_nodes or not material.node_tree:
            continue
        for node in material.node_tree.nodes:
            if node.type != "BSDF_PRINCIPLED":
                continue
            if "Metallic" in node.inputs:
                node.inputs["Metallic"].default_value = 0.0
            if "Roughness" in node.inputs:
                node.inputs["Roughness"].default_value = 0.7
            if "Specular IOR Level" in node.inputs:
                node.inputs["Specular IOR Level"].default_value = 0.5
    print("PBR_PREVIEW_FIXED")


def clean_stage(path: Path) -> None:
    """Drop duplicate material-subset mesh copies, review cameras, and force opaque."""
    from pxr import Usd, UsdShade

    opaque_materials = {
        "N00_000_00_Body_00_SKIN",
        "N00_000_00_Face_00_SKIN",
        "N00_000_00_HairBack_00_HAIR",
        "N00_000_Hair_00_HAIR",
        "N00_001_01_Bottoms_01_CLOTH",
        "N00_004_01_Tops_01_CLOTH",
        "N00_004_01_Shoes_01_CLOTH",
        "N00_000_00_FaceMouth_00_FACE",
        "MouthInner",
        "EarOuter",
        "EarInner",
        "EarInnerGradient",
        "Ahoge",
        "Headband",
        "HeadbandSide",
        "HeadbandAccent",
        "TrimWhite",
        "HoodieRib",
        "HoodieSeam",
        "HoodFold",
        "NeckSkin",
        "HeadbandTop",
        "DrawstringWhite",
        "DrawstringTip",
    }

    stage = Usd.Stage.Open(str(path))
    remove: set = set()
    for prim in stage.Traverse():
        if prim.GetTypeName() == "Mesh":
            parent = prim.GetParent()
            if parent and re.search(r"_\d+_0$", parent.GetName()):
                remove.add(parent.GetPath())
        if prim.GetName().startswith("ReviewCamera"):
            remove.add(prim.GetPath())
    for prim_path in remove:
        stage.RemovePrim(prim_path)

    for prim in stage.Traverse():
        if prim.GetTypeName() != "Material" or prim.GetName() not in opaque_materials:
            continue
        for child in prim.GetChildren():
            if child.GetTypeName() != "Shader":
                continue
            shader = UsdShade.Shader(child)
            if shader.GetShaderId() != "UsdPreviewSurface":
                continue
            opacity = shader.GetInput("opacity")
            if opacity:
                opacity.GetAttr().ClearConnections()
                opacity.Set(1.0)
    stage.GetRootLayer().Save()
    print(f"CLEANED_USD removed={len(remove)}")


def main() -> None:
    if not BLEND.exists():
        raise SystemExit(f"缺少 {BLEND}")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    texture_dir = OUT_DIR / "textures"
    if texture_dir.exists():
        shutil.rmtree(texture_dir)
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    scene = bpy.context.scene
    armature = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    if not armature.animation_data:
        raise SystemExit("骨架没有 animation_data")
    fix_preview_surface()
    ac.export_actions_to_usd(armature, scene, str(USDC), temp_prefix="phase1-usd-")
    clean_stage(USDC)

    textures = sorted((OUT_DIR / "textures").glob("*.png"))
    if not textures:
        raise SystemExit("没有导出贴图，USDZ 无法打包")
    args = ["usdzip", USDZ.name, USDC.name] + [path.relative_to(OUT_DIR).as_posix() for path in textures]
    print("USDZIP", " ".join(args))
    subprocess.run(args, cwd=str(OUT_DIR), check=True)
    print(f"USDZ {USDZ}")


main()
