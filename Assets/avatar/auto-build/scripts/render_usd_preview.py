"""Render a lit approximation of the exported USDZ with usdrecord.

Run:
    blender --background --factory-startup --python scripts/render_usd_preview.py
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from pxr import Gf, Usd, UsdGeom, UsdLux

ROOT = Path(__file__).resolve().parent.parent
USDC = ROOT / "out" / "minimate_phase0.usdc"
TEXTURES = ROOT / "out" / "textures"
OUT = ROOT / "renders" / "phase0"


def add_camera(stage: Usd.Stage, name: str, eye: tuple[float, float, float], rotation_y: float) -> None:
    camera = UsdGeom.Camera.Define(stage, f"/{name}")
    camera.GetProjectionAttr().Set("perspective")
    camera.GetFocalLengthAttr().Set(55)
    camera.GetClippingRangeAttr().Set(Gf.Vec2f(0.05, 100))
    xform = UsdGeom.Xformable(camera.GetPrim())
    xform.ClearXformOpOrder()
    xform.AddTranslateOp().Set(Gf.Vec3d(*eye))
    if rotation_y:
        xform.AddRotateYOp().Set(rotation_y)


def add_lights(stage: Usd.Stage) -> None:
    dome = UsdLux.DomeLight.Define(stage, "/PreviewDome")
    dome.GetIntensityAttr().Set(1.2)
    dome.GetColorAttr().Set(Gf.Vec3f(1.0, 1.0, 1.0))
    distant = UsdLux.DistantLight.Define(stage, "/PreviewKey")
    distant.GetIntensityAttr().Set(4.0)
    distant.GetColorAttr().Set(Gf.Vec3f(1.0, 1.0, 1.0))
    distant.GetAngleAttr().Set(0.5)
    xform = UsdGeom.Xformable(distant.GetPrim())
    xform.AddRotateXYZOp().Set(Gf.Vec3f(35, 0, 25))


def main() -> None:
    if not USDC.exists():
        raise SystemExit(f"缺少 {USDC}")
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="usd-preview-") as temp:
        temp_path = Path(temp)
        shutil.copyfile(USDC, temp_path / USDC.name)
        shutil.copytree(TEXTURES, temp_path / "textures")
        stage = Usd.Stage.Open(str(temp_path / USDC.name))
        add_camera(stage, "ReviewCameraFront", (0.0, 0.7, 3.8), 0.0)
        add_camera(stage, "ReviewCameraBack", (0.0, 0.7, -3.8), 180.0)
        add_lights(stage)
        stage.GetRootLayer().Save()

        for name, output in (
            ("ReviewCameraFront", OUT / "usd_preview_front.png"),
            ("ReviewCameraBack", OUT / "usd_preview_back.png"),
        ):
            subprocess.run(
                ["usdrecord", "--camera", name, "-w", "700", str(temp_path / USDC.name), str(output)],
                check=True,
            )
            print(f"USD_PREVIEW {output}")


main()
