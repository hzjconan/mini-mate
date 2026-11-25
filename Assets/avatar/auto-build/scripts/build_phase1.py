"""Build Phase 1 from the approved Phase 0 blend.

Phase 1 clothing pass:
  - cut the base long pants into shorts with a white hem;
  - rebuild white socks that conform to the lower leg;
  - turn the base T-shirt shell into a white/blue gradient hoodie:
    hem extension and rib band, long puffy sleeves with cuffs, hood,
    collar, drawstrings and a kangaroo pocket;
  - upgrade the cat-ear inner gradient.

The Phase 0 face topology and the 52 ARKit blendshapes are untouched.

Run:
    blender --background --factory-startup --python scripts/build_phase1.py
"""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, kdtree

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import avatar_common as ac  # noqa: E402

ROOT = SCRIPT_DIR.parent
CONFIG = ac.load_config()
PALETTE = CONFIG["palette"]
PHASE0_BLEND = ROOT / "work" / "phase0" / "minimate_phase0.blend"
OUT_BLEND = ROOT / "work" / "phase1" / "minimate_phase1.blend"
TEXTURE_DIR = ROOT / "textures" / "phase1"

SHORTS_CUT_Z = 0.375
SOCK_BOTTOM_Z = 0.072
SOCK_TOP_Z = 0.180
Z_GRAD_BOTTOM = 0.415
Z_GRAD_TOP = 0.86


# ---------------------------------------------------------------------------
# colour / texture helpers
# ---------------------------------------------------------------------------


def hex_rgb(value: str):
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))


def write_png(path: Path, width: int, height: int, pixel_fn) -> None:
    """Write an 8-bit sRGB PNG without external image dependencies."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    rows = []
    for y in range(height):
        v = 1.0 - y / max(1, height - 1)
        row = bytearray([0])
        for x in range(width):
            u = x / max(1, width - 1)
            row.extend(pixel_fn(u, v))
        rows.append(bytes(row))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
        + chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"TEXTURE {path.name} {path.stat().st_size} bytes")


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def lerp_color(a, b, t: float):
    return tuple(a[i] * (1.0 - t) + b[i] * t for i in range(3))


def generate_textures() -> dict[str, Path]:
    # 调色板原始上下差只有 ~9 级，PBR 光照下几乎看不出渐变；保持色相，
    # 顶部提亮、底部压暗并略微加深蓝色，让真机上能看到 review 的上浅下深。
    top = tuple(min(1.0, c * 1.06) for c in hex_rgb(PALETTE["hoodieTop"]))
    base_bottom = hex_rgb(PALETTE["hoodieBottom"])
    bottom = (
        base_bottom[0] * 0.86,
        base_bottom[1] * 0.90,
        min(1.0, base_bottom[2] * 0.96),
    )

    def hoodie_pixel(_u, v):
        t = smoothstep((v - 0.15) / 0.7)
        color = lerp_color(bottom, top, t)
        return tuple(round(c * 255) for c in color)

    hoodie_path = TEXTURE_DIR / "hoodie_gradient.png"
    write_png(hoodie_path, 64, 512, hoodie_pixel)

    ear_bottom = hex_rgb("#6FD6EA")
    ear_mid = hex_rgb("#B09AE6")
    ear_top = hex_rgb("#E79FCB")

    def ear_pixel(_u, v):
        if v < 0.5:
            color = lerp_color(ear_bottom, ear_mid, smoothstep(v / 0.5))
        else:
            color = lerp_color(ear_mid, ear_top, smoothstep((v - 0.5) / 0.5))
        return tuple(round(c * 255) for c in color)

    ear_path = TEXTURE_DIR / "ear_inner_gradient.png"
    write_png(ear_path, 32, 128, ear_pixel)

    neck_top = hex_rgb("#E6BAAE")
    neck_bottom = hex_rgb("#F5D5CA")

    def neck_pixel(_u, v):
        color = lerp_color(neck_bottom, neck_top, smoothstep(v))
        return tuple(round(c * 255) for c in color)

    neck_path = TEXTURE_DIR / "neck_skin.png"
    write_png(neck_path, 32, 128, neck_pixel)

    solids = {
        "shorts": PALETTE["shorts"],
        "trim": "#FFFFFF",
        "rib": "#E9EEF7",
        "seam": "#93A5C6",
        "hoodfold": "#B9C7DE",
        "headbandtop": "#CBDDF3",
    }
    paths = {"hoodie": hoodie_path, "ear": ear_path, "neck": neck_path}
    for name, hex_value in solids.items():
        color = hex_rgb(hex_value)
        path = TEXTURE_DIR / f"solid_{name}.png"
        write_png(path, 16, 16, lambda _u, _v, c=color: tuple(round(channel * 255) for channel in c))
        paths[name] = path

    rib_base = hex_rgb("#E9EEF7")
    rib_dark = hex_rgb("#D9E3F2")

    def rib_pixel(u, _v):
        stripe = 0.5 + 0.5 * math.cos(u * 2.0 * math.pi * 16)
        color = lerp_color(rib_base, rib_dark, 0.18 * stripe)
        return tuple(round(channel * 255) for channel in color)

    rib_path = TEXTURE_DIR / "rib_gradient.png"
    write_png(rib_path, 128, 32, rib_pixel)
    paths["rib"] = rib_path
    return paths


def load_image(name: str, path: Path):
    image = bpy.data.images.get(name)
    if image:
        bpy.data.images.remove(image)
    image = bpy.data.images.load(str(path.resolve()))
    image.name = name
    image.colorspace_settings.name = "sRGB"
    return image


def replace_mtoon_images(material, image) -> None:
    for node_name in ("Mtoon1BaseColorTexture.Image", "Mtoon1ShadeMultiplyTexture.Image"):
        node = material.node_tree.nodes.get(node_name)
        if node:
            node.image = image
    print(f"MTOON_TEXTURE {material.name} -> {image.name}")


def clone_mtoon(source, name: str, image):
    material = source.copy()
    material.name = name
    replace_mtoon_images(material, image)
    return material


def make_emissive_color_material(name: str, color, intensity: float = 1.0):
    """Unlit-looking material with a constant emissive colour.

    USD has no emission-strength input; write the intensity into the colour so
    the exporter keeps it (values above 1 are valid HDR in UsdPreviewSurface).
    """
    material = bpy.data.materials.get(name)
    if material:
        bpy.data.materials.remove(material)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Emission Color"].default_value = (
        color[0] * intensity,
        color[1] * intensity,
        color[2] * intensity,
        1.0,
    )
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_sock_white_material(
    name: str = "SockWhite",
    diffuse_color: tuple[float, float, float] = (1.0, 1.0, 1.0),
    emission_intensity: float = 0.70,
    roughness: float = 0.85,
):
    """Bright white cotton sock material with subtle 3D shading under ACES.

    Combines pure white diffuse reflection (preserving cylinder/cuff shading)
    with moderate linear HDR emission so the socks stay clean white in
    RealityKit without looking flat like an unlit sticker.
    """
    material = bpy.data.materials.get(name)
    if material:
        bpy.data.materials.remove(material)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*diffuse_color, 1.0)
    bsdf.inputs["Emission Color"].default_value = (
        emission_intensity,
        emission_intensity,
        emission_intensity,
        1.0,
    )
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.15
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_emissive_textured_material(name: str, image, strength: float = 1.0):
    material = bpy.data.materials.get(name)
    if material:
        bpy.data.materials.remove(material)
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def uv_gradient(world_point: Vector):
    v = (world_point.z - Z_GRAD_BOTTOM) / (Z_GRAD_TOP - Z_GRAD_BOTTOM)
    return (0.5, min(1.0, max(0.0, v)))


# ---------------------------------------------------------------------------
# mesh helpers
# ---------------------------------------------------------------------------


def make_tube(points: list[Vector], radii: list[float], segments: int = 8, closed: bool = False):
    rings = []
    for index, point in enumerate(points):
        if closed:
            tangent = points[(index + 1) % len(points)] - points[(index - 1) % len(points)]
        elif index == 0:
            tangent = points[1] - point
        elif index == len(points) - 1:
            tangent = point - points[index - 1]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        reference = Vector((0.0, 1.0, 0.0))
        if abs(tangent.dot(reference)) > 0.95:
            reference = Vector((1.0, 0.0, 0.0))
        side = tangent.cross(reference).normalized()
        up = side.cross(tangent).normalized()
        ring = []
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            ring.append(point + radii[index] * (math.cos(angle) * side + math.sin(angle) * up))
        rings.append(ring)

    vertices = [tuple(vertex) for ring in rings for vertex in ring]
    faces = []
    ring_pairs = [(i, i + 1) for i in range(len(rings) - 1)]
    if closed:
        ring_pairs.append((len(rings) - 1, 0))
    for first, second in ring_pairs:
        for segment in range(segments):
            nxt = (segment + 1) % segments
            faces.append(
                (
                    first * segments + segment,
                    first * segments + nxt,
                    second * segments + nxt,
                    second * segments + segment,
                )
            )
    if not closed:
        faces.append(tuple(range(segments - 1, -1, -1)))
        last = (len(rings) - 1) * segments
        faces.append(tuple(last + segment for segment in range(segments)))
    return vertices, faces


def loft_rings(rings: list[list[Vector]], closed: bool = True, cap_start: bool = False, cap_end: bool = False):
    segments = len(rings[0])
    vertices = [tuple(vertex) for ring in rings for vertex in ring]
    faces = []
    for index in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments if closed else segment + 1
            if not closed and nxt == segments:
                continue
            faces.append(
                (
                    index * segments + segment,
                    index * segments + nxt,
                    (index + 1) * segments + nxt,
                    (index + 1) * segments + segment,
                )
            )
    if cap_start:
        faces.append(tuple(range(segments - 1, -1, -1)))
    if cap_end:
        last = (len(rings) - 1) * segments
        faces.append(tuple(last + segment for segment in range(segments)))
    return vertices, faces


def chaikin(points: list[tuple[float, float]], iterations: int = 2) -> list[tuple[float, float]]:
    for _ in range(iterations):
        refined = []
        count = len(points)
        for index in range(count):
            ax, az = points[index]
            bx, bz = points[(index + 1) % count]
            refined.append((0.75 * ax + 0.25 * bx, 0.75 * az + 0.25 * bz))
            refined.append((0.25 * ax + 0.75 * bx, 0.25 * az + 0.75 * bz))
        points = refined
    return points


def ellipse_ring(z: float, rx: float, ry: float, center_y: float, segments: int = 32):
    ring = []
    for index in range(segments):
        angle = 2.0 * math.pi * index / segments
        ring.append(Vector((rx * math.cos(angle), center_y + ry * math.sin(angle), z)))
    return ring


def add_weights(obj, armature, weight_fn) -> None:
    for group in list(obj.vertex_groups):
        obj.vertex_groups.remove(group)
    cache = {}
    for index, vertex in enumerate(obj.data.vertices):
        world = armature.matrix_world @ vertex.co
        key = (round(world.x, 4), round(world.y, 4), round(world.z, 4))
        weights = cache.get(key)
        if weights is None:
            weights = weight_fn(world)
            cache[key] = weights
        for name, weight in weights.items():
            group = obj.vertex_groups.get(name)
            if not group:
                group = obj.vertex_groups.new(name=name)
            group.add([index], weight, "REPLACE")


def make_mesh(
    name: str,
    world_vertices,
    faces,
    material,
    armature,
    weight_fn,
    uv_fn=None,
    recalc: bool = False,
):
    local_vertices = [armature.matrix_world.inverted() @ Vector(vertex) for vertex in world_vertices]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(vertex) for vertex in local_vertices], [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True

    layer = mesh.uv_layers.new(name="UVMap")
    if uv_fn is None:
        for loop in layer.data:
            loop.uv = (0.5, 0.5)
    else:
        for polygon in mesh.polygons:
            for loop_index in polygon.loop_indices:
                vertex_index = mesh.loops[loop_index].vertex_index
                world = armature.matrix_world @ mesh.vertices[vertex_index].co
                layer.data[loop_index].uv = uv_fn(world)

    if recalc:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()

    assign_weights = weight_fn is not None
    if assign_weights:
        add_weights(obj, armature, weight_fn)

    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    return obj


def apply_solidify(obj, thickness: float, offset: float = -1.0) -> None:
    modifier = obj.modifiers.new("ClothThickness", "SOLIDIFY")
    modifier.thickness = thickness
    modifier.offset = offset
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def recalc_normals(obj) -> None:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


# ---------------------------------------------------------------------------
# body edits
# ---------------------------------------------------------------------------


def boundary_loops(bm, material_index: int) -> list[list[int]]:
    edges = [
        edge
        for edge in bm.edges
        if len(edge.link_faces) == 1 and edge.link_faces[0].material_index == material_index
    ]
    adjacency: dict[int, set[int]] = {}
    for edge in edges:
        a, b = edge.verts[0].index, edge.verts[1].index
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)
    loops = []
    remaining = set(adjacency)
    while remaining:
        start = remaining.pop()
        loop = [start]
        previous = None
        current = start
        while True:
            candidates = [n for n in adjacency.get(current, set()) if n != previous]
            if not candidates:
                break
            nxt = candidates[0]
            if nxt == start:
                break
            if nxt not in remaining:
                break
            remaining.discard(nxt)
            loop.append(nxt)
            previous, current = current, nxt
        if len(loop) > 20:
            loops.append(loop)
    return loops


def cut_shorts(armature, body) -> list[list[Vector]]:
    mesh = body.data
    matrix = body.matrix_world
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    remove = [
        face
        for face in bm.faces
        if face.material_index == 2 and (matrix @ face.calc_center_median()).z < SHORTS_CUT_Z
    ]
    bmesh.ops.delete(bm, geom=remove, context="FACES")
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    loops = boundary_loops(bm, 2)
    loop_points = []
    for loop in loops:
        points = [matrix @ bm.verts[index].co for index in loop]
        loop_points.append(points)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print(f"SHORTS_CUT removed={len(remove)} loops={[len(loop) for loop in loops]}")
    return loop_points


def inflate_tops(body, factor: float) -> None:
    bm = bmesh.new()
    bm.from_mesh(body.data)
    matrix = body.matrix_world
    vertices = {vertex for face in bm.faces if face.material_index == 3 for vertex in face.verts}
    for vertex in vertices:
        z = (matrix @ vertex.co).z
        bell = math.exp(-((z - 0.640) / 0.120) ** 2)
        local_factor = factor + 0.045 * bell
        vertex.co.x *= local_factor
        vertex.co.y *= local_factor
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    print(f"TOPS_INFLATED verts={len(vertices)} base={factor} chest={factor + 0.045:.3f}")


def raise_head(armature, raise_z: float = 0.040) -> None:
    """Raise the head/hair/accessories and the head rig to create a real neck."""
    names = (
        "Face",
        "Hair001",
        "Ahoge",
        "HeadbandSideL",
        "HeadbandSideR",
        "HeadbandAccentL",
        "HeadbandAccentR",
        "CatEarL",
        "CatEarR",
        "CatEarInnerL",
        "CatEarInnerR",
        "EarHeadband",
        "EarHeadbandSideL",
        "EarHeadbandSideR",
    )
    for name in names:
        obj = bpy.data.objects.get(name)
        if not obj:
            continue
        if obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                for point in key.data:
                    point.co.z += raise_z
        else:
            for vertex in obj.data.vertices:
                vertex.co.z += raise_z
        obj.data.update()

    body = bpy.data.objects.get("Body")
    if body:
        head_group = body.vertex_groups.get("J_Bip_C_Head")
        if head_group:
            for vertex in body.data.vertices:
                head_weight = 0.0
                for element in vertex.groups:
                    if element.group == head_group.index:
                        head_weight = element.weight
                        break
                if head_weight > 0.0:
                    vertex.co.z += raise_z * min(1.0, head_weight * 1.25)
            body.data.update()

    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    head_bone = armature.data.edit_bones.get("J_Bip_C_Head")
    neck_bone = armature.data.edit_bones.get("J_Bip_C_Neck")
    moved: set[str] = set()

    def collect(bone) -> None:
        if bone.name in moved:
            return
        moved.add(bone.name)
        for child in bone.children:
            collect(child)

    if head_bone:
        collect(head_bone)
    for bone in armature.data.edit_bones:
        if bone.name in moved:
            bone.head.z += raise_z
            bone.tail.z += raise_z
    if neck_bone:
        neck_bone.tail.z += raise_z
    bpy.ops.object.mode_set(mode="OBJECT")
    print(f"HEAD_RAISED {raise_z} bones={len(moved)}")


def recenter_irises(armature, offset: float = 0.007) -> None:
    """Move the iris/highlight shells outward on the face (was cross-eyed)."""
    face = bpy.data.objects.get("Face")
    if not face or not face.data.shape_keys:
        print("IRIS_RECENTER_SKIPPED")
        return
    indices: set[int] = set()
    for slot_index, slot in enumerate(face.material_slots):
        name = slot.material.name if slot.material else ""
        if "EyeIris" not in name and "EyeHighlight" not in name:
            continue
        for polygon in face.data.polygons:
            if polygon.material_index == slot_index:
                indices.update(polygon.vertices)
    basis = face.data.shape_keys.key_blocks.get("Basis")
    if not basis:
        print("IRIS_RECENTER_SKIPPED")
        return
    matrix = face.matrix_world
    deltas: dict[int, float] = {}
    for vertex_index in indices:
        world_x = (matrix @ basis.data[vertex_index].co).x
        sign = 1.0 if world_x > 0 else -1.0
        deltas[vertex_index] = -sign * offset
    for key in face.data.shape_keys.key_blocks:
        for vertex_index, delta in deltas.items():
            key.data[vertex_index].co.x += delta
    face.data.update()
    print(f"IRIS_RECENTERED verts={len(indices)} offset={offset}")


def bake_idle_mouth(face, amount: float = 0.15) -> None:
    """Bake a small jaw-open baseline so the idle mouth is visibly open.

    The skin mouth line alone read as a horizontal line across the mouth.
    Opening the jaw slightly reveals the inner mouth at rest; all shape keys
    receive the same baseline so expressions keep their relative motion.
    """
    if not face or not face.data.shape_keys:
        print("IDLE_MOUTH_SKIPPED")
        return
    keys = face.data.shape_keys.key_blocks
    basis = keys.get("Basis")
    jaw = keys.get("jawOpen")
    if not basis or not jaw:
        print("IDLE_MOUTH_SKIPPED")
        return
    count = len(basis.data)
    deltas = [(jaw.data[i].co - basis.data[i].co) * amount for i in range(count)]
    for key in keys:
        for i in range(count):
            key.data[i].co += deltas[i]
    face.data.update()
    print(f"IDLE_MOUTH_BAKED amount={amount}")


def reshape_ahoge() -> None:
    """Shorten the ahoge into a smooth curl, updating the skinned mesh in place."""
    obj = bpy.data.objects.get("Ahoge")
    if not obj:
        print("AHOGE_SKIPPED")
        return
    mesh = obj.data
    material = mesh.materials[0] if mesh.materials else bpy.data.materials.get("Ahoge")
    matrix = obj.matrix_world
    inverse = matrix.inverted()
    segments = 8
    ring_count = len(mesh.vertices) // segments
    if ring_count != 7 or len(mesh.vertices) != 56:
        print(f"AHOGE_SKIPPED verts={len(mesh.vertices)}")
        return
    centers = []
    radii = []
    for ring in range(ring_count):
        verts = [matrix @ mesh.vertices[ring * segments + i].co for i in range(segments)]
        center = sum(verts, Vector((0.0, 0.0, 0.0))) / segments
        centers.append(center)
        radii.append(sum((v - center).length for v in verts) / segments)
    root = centers[0]
    control = (
        (0.000, 0.0, 0.000),
        (-0.004, 0.0, 0.025),
        (-0.008, 0.0, 0.050),
        (0.000, 0.0, 0.075),
        (0.018, 0.0, 0.094),
        (0.042, 0.0, 0.100),
        (0.062, 0.0, 0.086),
        (0.068, 0.0, 0.065),
        (0.056, 0.0, 0.048),
        (0.040, 0.0, 0.045),
    )

    def chaikin(points, iterations=2):
        result = [Vector(point) for point in points]
        for _ in range(iterations):
            smooth = [result[0]]
            for a, b in zip(result, result[1:]):
                smooth.append(a * 0.75 + b * 0.25)
                smooth.append(a * 0.25 + b * 0.75)
            smooth.append(result[-1])
            result = smooth
        return result

    offsets = chaikin(control, 2)
    points = [root + offset for offset in offsets]
    count = len(points)
    profiles = [radii[0] * (1.0 - i / max(count - 1, 1)) ** 0.85 + radii[-1] * (i / max(count - 1, 1)) for i in range(count)]
    rings = []
    for index, point in enumerate(points):
        if index == 0:
            tangent = points[1] - point
        elif index == count - 1:
            tangent = point - points[index - 1]
        else:
            tangent = points[index + 1] - points[index - 1]
        tangent.normalize()
        reference = Vector((0.0, 1.0, 0.0))
        if abs(tangent.dot(reference)) > 0.95:
            reference = Vector((1.0, 0.0, 0.0))
        side = tangent.cross(reference).normalized()
        up = side.cross(tangent).normalized()
        ring = []
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            ring.append(point + profiles[index] * (math.cos(angle) * side + math.sin(angle) * up))
        rings.append(ring)
    vertices = [tuple(inverse @ vertex) for ring in rings for vertex in ring]
    faces = []
    for ring_index in range(len(rings) - 1):
        for segment in range(segments):
            nxt = (segment + 1) % segments
            a = ring_index * segments + segment
            b = ring_index * segments + nxt
            c = (ring_index + 1) * segments + nxt
            d = (ring_index + 1) * segments + segment
            faces.append((a, b, c, d))
    faces.append(tuple(range(segments - 1, -1, -1)))
    last = (len(rings) - 1) * segments
    faces.append(tuple(last + segment for segment in range(segments)))
    mesh.clear_geometry()
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    mesh.materials.clear()
    if material:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        ring = loop.vertex_index // segments
        t = ring / max(len(rings) - 1, 1)
        uv_layer.data[loop.index].uv = (0.95, 0.95 - 0.90 * t)
    group = obj.vertex_groups.get("J_Bip_C_Head")
    if not group:
        group = obj.vertex_groups.new(name="J_Bip_C_Head")
    group.add(list(range(len(mesh.vertices))), 1.0, "REPLACE")
    print(f"AHOGE_RESHAPED rings={len(rings)} height={max(p.z for p in points) - root.z:.3f} curl={max(p.x for p in points) - root.x:.3f}")


def add_neck(armature, material) -> None:
    """A real skin neck cylinder bridging the chest and the raised head."""
    rings = []
    for z, radius in ((0.785, 0.042), (0.800, 0.039), (0.820, 0.036), (0.840, 0.034), (0.862, 0.032)):
        ring = []
        for index in range(16):
            angle = 2.0 * math.pi * index / 16
            ring.append(Vector((radius * math.cos(angle), 0.005 + radius * math.sin(angle), z)))
        rings.append(ring)
    vertices, faces = loft_rings(rings, closed=True)

    def neck_weights(point: Vector):
        if point.z < 0.800:
            return {"J_Bip_C_UpperChest": 0.55, "J_Bip_C_Neck": 0.45}
        if point.z < 0.830:
            return {"J_Bip_C_Neck": 0.80, "J_Bip_C_Head": 0.20}
        return {"J_Bip_C_Head": 0.80, "J_Bip_C_Neck": 0.20}

    def neck_uv(point: Vector):
        return (0.5, min(1.0, max(0.0, (point.z - 0.785) / (0.862 - 0.785))))

    make_mesh("Neck", vertices, faces, material, armature, neck_weights, uv_fn=neck_uv)
    print("NECK_DONE")


def set_tops_uvs(body) -> None:
    mesh = body.data
    layer = mesh.uv_layers.get("UVMap")
    if not layer:
        layer = mesh.uv_layers.new(name="UVMap")
    matrix = body.matrix_world
    for polygon in mesh.polygons:
        if polygon.material_index != 3:
            continue
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            world = matrix @ mesh.vertices[vertex_index].co
            v = (world.z - Z_GRAD_BOTTOM) / (Z_GRAD_TOP - Z_GRAD_BOTTOM)
            layer.data[loop_index].uv = (0.5, min(1.0, max(0.0, v)))
    print("TOPS_UVS_REMAPPED")


def body_ray_hit(body, origin: Vector, direction: Vector, distance: float = 0.4):
    inverse = body.matrix_world.inverted()
    local_origin = inverse @ origin
    local_direction = inverse.to_3x3() @ direction
    hit, location, _normal, face_index = body.ray_cast(local_origin, local_direction, distance=distance)
    if not hit:
        return None
    return body.matrix_world @ location


class NearestSkinWeights:
    def __init__(self, body):
        self.body = body
        skin_verts = sorted(
            {
                vertex_index
                for polygon in body.data.polygons
                if polygon.material_index == 0
                for vertex_index in polygon.vertices
            }
        )
        self.indices = skin_verts
        self.tree = kdtree.KDTree(len(skin_verts))
        for slot, vertex_index in enumerate(skin_verts):
            self.tree.insert(body.matrix_world @ body.data.vertices[vertex_index].co, slot)
        self.tree.balance()
        self.names = {group.index: group.name for group in body.vertex_groups}

    def __call__(self, point: Vector):
        accumulate: dict[str, float] = {}
        for _co, slot, dist in self.tree.find_n(point, 6):
            vertex_index = self.indices[slot]
            weight = 1.0 / (dist + 0.004) ** 2
            for element in self.body.data.vertices[vertex_index].groups:
                name = self.names.get(element.group)
                if name and element.weight > 0.02:
                    accumulate[name] = accumulate.get(name, 0.0) + element.weight * weight
        total = sum(accumulate.values())
        if total <= 0:
            return {"J_Bip_C_Hips": 1.0}
        return {name: value / total for name, value in accumulate.items() if value / total > 0.01}


def constant_weights(mapping: dict[str, float]):
    return lambda _point: mapping


# ---------------------------------------------------------------------------
# clothing parts
# ---------------------------------------------------------------------------


def add_shorts_hem_bands(armature, body, material, nearest):
    """Clean horizontal hem bands; the cut boundary also contains side seams."""
    mesh = body.data
    matrix = body.matrix_world
    shorts_vertices = {
        vertex_index
        for polygon in mesh.polygons
        if polygon.material_index == 2
        for vertex_index in polygon.vertices
    }
    for sign, side in ((1, "L"), (-1, "R")):
        points = [
            matrix @ mesh.vertices[index].co
            for index in shorts_vertices
            if 0.368 <= (matrix @ mesh.vertices[index].co).z <= 0.392
            and (matrix @ mesh.vertices[index].co).x * sign > 0.0
        ]
        if len(points) < 8:
            print(f"SHORTS_HEM_{side}_SKIPPED n={len(points)}")
            continue
        center_x = (min(p.x for p in points) + max(p.x for p in points)) / 2.0
        center_y = (min(p.y for p in points) + max(p.y for p in points)) / 2.0
        radius_x = (max(p.x for p in points) - min(p.x for p in points)) / 2.0 + 0.004
        radius_y = (max(p.y for p in points) - min(p.y for p in points)) / 2.0 + 0.004
        rings = []
        for z in (0.362, 0.374, 0.388):
            ring = []
            for index in range(24):
                angle = 2.0 * math.pi * index / 24
                ring.append(
                    Vector(
                        (
                            center_x + radius_x * math.cos(angle),
                            center_y + radius_y * math.sin(angle),
                            z,
                        )
                    )
                )
            rings.append(ring)
        vertices, faces = loft_rings(rings, closed=True)
        obj = make_mesh(f"ShortsHem{side}", vertices, faces, material, armature, nearest)
        print(
            f"SHORTS_HEM {side} center=({center_x:.3f},{center_y:.3f}) "
            f"r=({radius_x:.3f},{radius_y:.3f}) verts={len(obj.data.vertices)}"
        )


def add_socks(armature, body, nearest, material):
    from mathutils.bvhtree import BVHTree

    skin_indices = {
        vertex_index
        for polygon in body.data.polygons
        if polygon.material_index == 0
        for vertex_index in polygon.vertices
    }
    skin_world = [(body.matrix_world @ body.data.vertices[index].co, index) for index in skin_indices]

    # Raycast only the skin: the shoe lives in the same mesh, and the sock must
    # follow the ankle/foot surface inside the shoe instead of the shoe shell.
    skin_vertices: list[Vector] = []
    skin_faces: list[list[int]] = []
    skin_index_map: dict[int, int] = {}
    for polygon in body.data.polygons:
        if polygon.material_index != 0:
            continue
        face = []
        for vertex_index in polygon.vertices:
            local = skin_index_map.get(vertex_index)
            if local is None:
                local = len(skin_vertices)
                skin_index_map[vertex_index] = local
                skin_vertices.append(body.matrix_world @ body.data.vertices[vertex_index].co)
            face.append(local)
        skin_faces.append(face)
    skin_bvh = BVHTree.FromPolygons(skin_vertices, skin_faces, all_triangles=False)

    # A normal sock tucks into the shoe and has a snug cuff, not a floating
    # open-ended tube.  The lowest rings run below the shoe top (z≈0.066) so no
    # ankle skin shows between sock and shoe; the top ring is pulled inside the
    # skin so the sock ends in a cuff instead of an open rim.
    segments = 20
    shoe_collar_z = SOCK_BOTTOM_Z
    levels = [
        # The shoe collar is wider than the ankle; a small outward flare at the
        # opening keeps skin from showing between the sock and the shoe.
        (0.048, 0.0060),
        (0.060, 0.0055),
        (shoe_collar_z, 0.0050),
        (0.090, 0.0038),
        (0.112, 0.0038),
        (0.138, 0.0038),
        (0.158, 0.0038),
        # Rounded cuff: a short rolled lip that tucks back into the skin.
        (0.164, 0.0048),
        (0.170, 0.0055),
        (0.175, 0.0060),
        (0.179, 0.0055),
        (SOCK_TOP_Z + 0.0015, 0.0035),
        (SOCK_TOP_Z + 0.0030, 0.0003),
        (SOCK_TOP_Z + 0.0035, -0.0020),
    ]

    def ring_center(z: float, sign: int) -> Vector | None:
        window = 0.018 if z >= shoe_collar_z else 0.006
        slice_points = [
            point
            for point, _index in skin_world
            if abs(point.z - z) < window and point.x * sign > 0.01
        ]
        if len(slice_points) < 4:
            return None
        return sum(slice_points, Vector()) / len(slice_points)

    def ray_ring(center: Vector, z: float, sign: int) -> list[tuple[Vector, Vector]]:
        ring = []
        misses = 0
        for segment in range(segments):
            angle = 2.0 * math.pi * segment / segments
            direction = Vector((math.cos(angle), math.sin(angle), 0.0))
            hit, _normal, _index, _distance = skin_bvh.ray_cast(
                Vector((center.x, center.y, z)), direction, 0.16
            )
            if hit is None:
                misses += 1
                hit = Vector((center.x, center.y, z)) + direction * 0.045
            radial = Vector((hit.x - center.x, hit.y - center.y, 0.0))
            if radial.length < 1e-5:
                radial = direction
            ring.append((hit, radial.normalized()))
        if misses:
            print(f"SOCK_RAY {sign} z={z:.3f} misses={misses}")
        return ring

    for sign, side in ((1, "L"), (-1, "R")):
        rings = []
        for z, offset in levels:
            center = ring_center(z, sign)
            if center is None:
                print(f"SOCK_RING {side} z={z:.3f} skipped=no slice")
                continue
            hits = ray_ring(center, z, sign)
            rings.append([hit + normal * offset for hit, normal in hits])
            print(f"SOCK_RING {side} z={z:.3f} center=({center.x:.3f},{center.y:.3f}) offset={offset:.4f}")

        if len(rings) < 3:
            print(f"SOCK_{side}_SKIPPED rings={len(rings)}")
            continue
        vertices, faces = loft_rings(rings, closed=True)
        obj = make_mesh(f"Sock{side}", vertices, faces, material, armature, nearest)
        print(f"SOCK {side} rings={len(rings)} verts={len(obj.data.vertices)}")


def add_hoodie_hem(armature, gradient_material, rib_material):
    hips = constant_weights({"J_Bip_C_Hips": 0.85, "J_Bip_C_Spine": 0.15})

    def band_rib_uv(point: Vector):
        angle = math.atan2(point.y + 0.0085, point.x)
        u = (angle / (2.0 * math.pi)) % 1.0
        v = (point.z - 0.415) / 0.030
        return (u, min(1.0, max(0.0, v)))
    extension_rings = [
        ellipse_ring(0.425, 0.198, 0.145, -0.0085, 32),
        ellipse_ring(0.438, 0.199, 0.146, -0.0085, 32),
        ellipse_ring(0.462, 0.202, 0.148, -0.0085, 32),
        ellipse_ring(0.487, 0.205, 0.150, -0.0085, 32),
    ]
    vertices, faces = loft_rings(extension_rings, closed=True)
    make_mesh(
        "HoodieHemExtension",
        vertices,
        faces,
        gradient_material,
        armature,
        hips,
        uv_fn=uv_gradient,
    )
    band_rings = [
        ellipse_ring(0.415, 0.199, 0.146, -0.0085, 32),
        ellipse_ring(0.430, 0.200, 0.147, -0.0085, 32),
        ellipse_ring(0.445, 0.201, 0.148, -0.0085, 32),
    ]
    vertices, faces = loft_rings(band_rings, closed=True)
    make_mesh("HoodieHemBand", vertices, faces, rib_material, armature, hips, uv_fn=band_rib_uv)
    print("HOODIE_HEM_DONE")


def add_sleeves(armature, nearest, gradient_material, rib_material):
    def cuff_rib_uv(point: Vector):
        angle = math.atan2(point.y - 0.005, point.x)
        u = (angle / (2.0 * math.pi)) % 1.0
        v = (point.z - 0.500) / 0.040
        return (u, min(1.0, max(0.0, v)))

    # A single puffy sleeve from the shoulder to the wrist.  The base T-shirt's
    # fitted short sleeve stays hidden inside it.  Centres follow the actual arm
    # mesh (the imported armature's arm bones are offset from the mesh).
    sleeve_profile = [
        ((0.120, 0.010, 0.792), 0.042),
        ((0.136, 0.013, 0.758), 0.052),
        ((0.151, 0.014, 0.718), 0.058),
        ((0.168, 0.012, 0.678), 0.059),
        ((0.188, 0.009, 0.635), 0.057),
        ((0.212, 0.006, 0.592), 0.053),
        ((0.233, 0.002, 0.550), 0.047),
        ((0.244, 0.000, 0.522), 0.041),
    ]
    cuff_profile = [
        ((0.242, 0.001, 0.532), 0.0445),
        ((0.245, 0.000, 0.514), 0.0440),
        ((0.247, 0.000, 0.502), 0.0425),
    ]
    for sign, side in ((1, "L"), (-1, "R")):
        points = [Vector((sign * x, y, z)) for (x, y, z), _radius in sleeve_profile]
        radii = [radius for _point, radius in sleeve_profile]
        vertices, faces = make_tube(points, radii, segments=12, closed=False)
        make_mesh(
            f"HoodieSleeve{side}",
            vertices,
            faces,
            gradient_material,
            armature,
            nearest,
            uv_fn=uv_gradient,
            recalc=True,
        )
        cuff_points = [Vector((sign * x, y, z)) for (x, y, z), _radius in cuff_profile]
        cuff_radii = [radius for _point, radius in cuff_profile]
        vertices, faces = make_tube(cuff_points, cuff_radii, segments=12, closed=False)
        make_mesh(f"HoodieCuff{side}", vertices, faces, rib_material, armature, nearest, uv_fn=cuff_rib_uv, recalc=True)
        print(f"SLEEVE {side} done")


def add_pocket(armature, body, gradient_material, seam_material):
    xs = [-0.095 + 0.190 * i / 8 for i in range(9)]
    zs = [0.492 + (0.600 - 0.492) * j / 4 for j in range(5)]
    center_z = (zs[0] + zs[-1]) / 2.0
    half_z = (zs[-1] - zs[0]) / 2.0
    grid = []
    for j, z in enumerate(zs):
        row = []
        for i, x in enumerate(xs):
            hit = body_ray_hit(body, Vector((x, -0.5, z)), Vector((0, 1, 0)), distance=0.6)
            if hit is None:
                hit = Vector((x, -0.15, z))
            dx = x / 0.095
            dz = (z - center_z) / half_z
            bulge = max(0.0, 1.0 - (dx * dx + dz * dz))
            offset = 0.005 + 0.009 * bulge
            row.append(Vector((x, hit.y - offset, z)))
        grid.append(row)
    vertices = [vertex for row in grid for vertex in row]
    faces = []
    for j in range(4):
        for i in range(8):
            if (i in (0, 7)) and (j in (0, 3)):
                continue
            a = j * 9 + i
            b = a + 1
            c = a + 10
            d = a + 9
            faces.append((a, b, c, d))
    weights = constant_weights({"J_Bip_C_Hips": 0.7, "J_Bip_C_Spine": 0.3})
    obj = make_mesh(
        "HoodiePocket",
        vertices,
        faces,
        gradient_material,
        armature,
        weights,
        uv_fn=uv_gradient,
    )
    apply_solidify(obj, 0.005, offset=-1.0)
    add_weights(obj, armature, weights)
    print(f"POCKET verts={len(obj.data.vertices)}")

    top_z = zs[-1]
    seam_points = []
    for i, x in enumerate(xs):
        hit = body_ray_hit(body, Vector((x, -0.5, top_z)), Vector((0, 1, 0)), distance=0.6)
        if hit is None:
            hit = Vector((x, -0.15, top_z))
        seam_points.append(Vector((x, hit.y - 0.008, top_z)))
    vertices, faces = make_tube(seam_points, [0.0022] * len(seam_points), segments=5, closed=False)
    make_mesh("HoodiePocketSeamTop", vertices, faces, seam_material, armature, weights, recalc=True)
    for sign, side in ((1, "L"), (-1, "R")):
        start = Vector((sign * 0.095, 0.0, 0.600))
        end = Vector((sign * 0.070, 0.0, 0.552))
        start_hit = body_ray_hit(body, Vector((start.x, -0.5, start.z)), Vector((0, 1, 0)), distance=0.6)
        end_hit = body_ray_hit(body, Vector((end.x, -0.5, end.z)), Vector((0, 1, 0)), distance=0.6)
        if start_hit is None:
            start_hit = Vector((start.x, -0.14, start.z))
        if end_hit is None:
            end_hit = Vector((end.x, -0.15, end.z))
        diagonal = [
            Vector((start.x, start_hit.y - 0.008, start.z)),
            Vector((end.x, end_hit.y - 0.011, end.z)),
        ]
        vertices, faces = make_tube(diagonal, [0.0022, 0.0022], segments=5, closed=False)
        make_mesh(f"HoodiePocketSeam{side}", vertices, faces, seam_material, armature, weights, recalc=True)


def add_v_neck(armature, body, skin_material, trim_material, nearest):
    """A skin-coloured V opening in front of the crew neck, with a fabric trim."""
    rows = [
        (0.828, 0.048),
        (0.816, 0.055),
        (0.804, 0.058),
        (0.792, 0.054),
        (0.780, 0.048),
        (0.768, 0.040),
        (0.756, 0.030),
        (0.744, 0.018),
    ]
    point_z = 0.734
    columns = 5
    grid = []
    for z, half_width in rows:
        row = []
        for index in range(columns):
            x = -half_width + 2.0 * half_width * index / (columns - 1)
            hit = body_ray_hit(body, Vector((x, -0.5, z)), Vector((0, 1, 0)), distance=0.6)
            y = hit.y - 0.004 if hit is not None else -0.12
            row.append(Vector((x, y, z)))
        grid.append(row)
    point_hit = body_ray_hit(body, Vector((0.0, -0.5, point_z)), Vector((0, 1, 0)), distance=0.6)
    point = Vector((0.0, point_hit.y - 0.004 if point_hit is not None else -0.15, point_z))

    vertices = [vertex for row in grid for vertex in row]
    faces = []
    for row_index in range(len(rows) - 1):
        for column in range(columns - 1):
            a = row_index * columns + column
            b = a + 1
            c = a + columns + 1
            d = a + columns
            faces.append((d, c, b, a))
    last_row = (len(rows) - 1) * columns
    point_index = len(vertices)
    for column in range(columns - 1):
        faces.append((last_row + column + 1, last_row + column, point_index))
    vertices.append(point)

    def uv(point_vertex: Vector):
        v = (point_vertex.z - point_z) / (0.828 - point_z)
        return (0.5, min(1.0, max(0.0, v)))

    # Cut the front T-shirt shell inside the V so the real body skin shows
    # instead of a flat skin decal.
    mesh = body.data
    matrix = body.matrix_world
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()

    def half_width_at(z: float) -> float:
        sorted_rows = sorted(rows, key=lambda item: item[0])
        if z <= sorted_rows[0][0]:
            return sorted_rows[0][1]
        if z >= sorted_rows[-1][0]:
            return sorted_rows[-1][1]
        for first, second in zip(sorted_rows, sorted_rows[1:]):
            if first[0] <= z <= second[0]:
                t = (z - first[0]) / max(1e-6, second[0] - first[0])
                return first[1] * (1.0 - t) + second[1] * t
        return 0.0

    remove = []
    for face in bm.faces:
        if face.material_index != 3:
            continue
        center = matrix @ face.calc_center_median()
        if center.y >= (0.040 if center.z >= 0.800 else -0.020):
            continue
        if not (0.734 <= center.z <= 0.845):
            continue
        if abs(center.x) < half_width_at(center.z) + 0.006:
            remove.append(face)
    bmesh.ops.delete(bm, geom=remove, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    print(f"V_NECK_CUT removed={len(remove)}")

    for sign, side in ((1, "L"), (-1, "R")):
        trim_points = []
        for row_index in range(1, len(rows)):
            z, half_width = rows[row_index]
            x = sign * half_width
            y = (grid[row_index][-1].y if sign > 0 else grid[row_index][0].y) - 0.001
            trim_points.append(Vector((x, y, z)))
        trim_points.append(Vector((sign * 0.003, point.y - 0.001, point_z)))
        trim_vertices, trim_faces = make_tube(
            trim_points, [0.007] * len(trim_points), segments=8, closed=False
        )
        make_mesh(
            f"NecklineTrim{side}",
            trim_vertices,
            trim_faces,
            trim_material,
            armature,
            nearest,
            uv_fn=uv_gradient,
            recalc=True,
        )
    print("V_NECK_DONE")


def add_collar(armature, gradient_material):
    weights = constant_weights({"J_Bip_C_Neck": 0.5, "J_Bip_C_UpperChest": 0.5})
    points = []
    radii = []
    for index in range(25):
        angle = math.radians(55.0 + 250.0 * index / 24)
        x = 0.075 * math.sin(angle)
        y = 0.005 - 0.065 * math.cos(angle)
        z = 0.803 + 0.018 * (0.5 - 0.5 * math.cos(angle))
        points.append(Vector((x, y, z)))
        radii.append(0.013 + 0.008 * (0.5 - 0.5 * math.cos(angle)))
    vertices, faces = make_tube(points, radii, segments=8, closed=False)
    make_mesh(
        "HoodieCollar",
        vertices,
        faces,
        gradient_material,
        armature,
        weights,
        uv_fn=uv_gradient,
        recalc=True,
    )
    print("COLLAR_DONE")


def add_hood(armature, gradient_material, fold_material, rib_material):
    weights = constant_weights({"J_Bip_C_UpperChest": 0.75, "J_Bip_C_Neck": 0.25})

    def hood_uv(point: Vector):
        u, v = uv_gradient(point)
        return (u, max(0.0, v - 0.18))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=1.0)
    bm.faces.ensure_lookup_table()
    delete = [face for face in bm.faces if face.calc_center_median().y < 0.0]
    bmesh.ops.delete(bm, geom=delete, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    center = Vector((0.0, 0.095, 0.735))
    scale = Vector((0.185, 0.105, 0.135))
    for vertex in bm.verts:
        vertex.co = Vector(
            (
                vertex.co.x * scale.x + center.x,
                vertex.co.y * scale.y + center.y,
                vertex.co.z * scale.z + center.z,
            )
        )
    index_map = {vertex: index for index, vertex in enumerate(bm.verts)}
    vertices = [vertex.co.copy() for vertex in bm.verts]
    faces = [tuple(index_map[vertex] for vertex in face.verts) for face in bm.faces]
    bm.free()
    obj = make_mesh(
        "HoodieHood",
        vertices,
        faces,
        gradient_material,
        armature,
        weights,
        uv_fn=hood_uv,
    )
    apply_solidify(obj, 0.012, offset=-1.0)
    recalc_normals(obj)
    add_weights(obj, armature, weights)
    print(f"HOOD verts={len(obj.data.vertices)} faces={len(obj.data.polygons)}")

    seam_points = []
    for index in range(9):
        t = index / 8
        z = 0.858 - t * 0.225
        ratio = (z - center.z) / scale.z
        y = center.y + scale.y * math.sqrt(max(0.0, 1.0 - ratio * ratio))
        seam_points.append(Vector((0.0, y + 0.0015, z)))
    vertices, faces = make_tube(seam_points, [0.0022] * len(seam_points), segments=5, closed=False)
    make_mesh("HoodieHoodSeam", vertices, faces, fold_material, armature, weights, recalc=True)

    for sign, side in ((1, "L"), (-1, "R")):
        fold_points = []
        for index in range(10):
            z = 0.840 - index * (0.840 - 0.640) / 9
            x = sign * 0.075
            term = 1.0 - (x / scale.x) ** 2 - ((z - center.z) / scale.z) ** 2
            y = center.y + scale.y * math.sqrt(max(0.0, term))
            fold_points.append(Vector((x, y + 0.0015, z)))
        vertices, faces = make_tube(fold_points, [0.0022] * len(fold_points), segments=5, closed=False)
        make_mesh(f"HoodieHoodFold{side}", vertices, faces, fold_material, armature, weights, recalc=True)

    hem_points = []
    for index in range(9):
        x = -0.130 + 0.260 * index / 8
        z = 0.645
        term = 1.0 - (x / scale.x) ** 2 - ((z - center.z) / scale.z) ** 2
        y = center.y + scale.y * math.sqrt(max(0.0, term))
        hem_points.append(Vector((x, y + 0.0015, z)))
    vertices, faces = make_tube(hem_points, [0.0075] * len(hem_points), segments=8, closed=False)
    make_mesh("HoodieHoodHem", vertices, faces, rib_material, armature, weights, recalc=True)


def add_drawstrings(armature, body, string_material, tip_material):
    weights = constant_weights({"J_Bip_C_UpperChest": 0.75, "J_Bip_C_Neck": 0.25})
    for sign, side in ((1, "L"), (-1, "R")):
        start_hit = body_ray_hit(body, Vector((sign * 0.052, -0.5, 0.795)), Vector((0, 1, 0)), distance=0.6)
        start_y = (start_hit.y - 0.017) if start_hit is not None else -0.09
        points = [Vector((sign * 0.052, start_y, 0.795))]
        for z in (0.778, 0.758, 0.738, 0.718, 0.698, 0.678, 0.660):
            x = sign * (0.052 + (0.795 - z) * 0.02)
            hit = body_ray_hit(body, Vector((x, -0.5, z)), Vector((0, 1, 0)), distance=0.6)
            if hit is None:
                hit = Vector((x, -0.15, z))
            offset = 0.017 if z >= 0.750 else (0.012 if z >= 0.735 else 0.010)
            points.append(Vector((x, hit.y - offset, z)))
        vertices, faces = make_tube(points, [0.0034] * len(points), segments=6, closed=False)
        make_mesh(f"Drawstring{side}", vertices, faces, string_material, armature, weights, recalc=True)
        tip_start = points[-1]
        tip_end = tip_start + Vector((0.0, 0.0, -0.014))
        vertices, faces = make_tube([tip_start, tip_end], [0.0038, 0.0038], segments=6, closed=False)
        make_mesh(f"DrawstringTip{side}", vertices, faces, tip_material, armature, weights, recalc=True)
        print(f"DRAWSTRING {side} points={len(points)}")


def rebuild_cat_ears(armature, band_material) -> None:
    """Replace the angular ear prisms with smaller, rounded cat ears."""
    hair = bpy.data.objects.get("Hair001")
    hair_inverse = hair.matrix_world.inverted() if hair else None
    hair_rotation = hair_inverse.to_3x3() if hair_inverse else None

    def hair_top(x: float, y: float):
        if not hair or hair_inverse is None or hair_rotation is None:
            return None
        origin = hair_inverse @ Vector((x, y, 1.6))
        direction = hair_rotation @ Vector((0.0, 0.0, -1.0))
        hit, location, _normal, _index = hair.ray_cast(origin, direction, distance=1.5)
        return (hair.matrix_world @ location).z if hit else None

    for side, sign, outer_name, inner_name in (
        ("L", -1.0, "CatEarL", "CatEarInnerL"),
        ("R", 1.0, "CatEarR", "CatEarInnerR"),
    ):
        old_outer = bpy.data.objects.get(outer_name)
        old_inner = bpy.data.objects.get(inner_name)
        if not old_outer:
            print(f"EAR_REBUILD_MISSING {outer_name}")
            continue
        world = [old_outer.matrix_world @ vertex.co for vertex in old_outer.data.vertices]
        center_x = sign * 0.090
        base_z = 1.125
        front_y = min(point.y for point in world) - 0.002
        back_y = max(point.y for point in world) - 0.006
        head_group = old_outer.vertex_groups[0].name if old_outer.vertex_groups else "J_Bip_C_Head"
        outer_material = old_outer.data.materials[0] if old_outer.data.materials else None
        inner_material = old_inner.data.materials[0] if old_inner and old_inner.data.materials else None
        for obj in (old_outer, old_inner):
            if obj:
                bpy.data.objects.remove(obj, do_unlink=True)

        half_width = 0.064
        height = 0.148
        outline = [
            (-half_width, 0.012),
            (-half_width * 0.70, 0.0),
            (half_width * 0.70, 0.0),
            (half_width, 0.012),
            (half_width * 0.82, height * 0.38),
            (half_width * 0.52, height * 0.72),
            (half_width * 0.22, height * 0.93),
            (0.0, height * 0.985),
            (-half_width * 0.22, height * 0.93),
            (-half_width * 0.52, height * 0.72),
            (-half_width * 0.82, height * 0.38),
        ]
        leaned = [
            (
                center_x + x + sign * 0.018 * ((z / height) ** 1.4),
                base_z + z,
            )
            for x, z in outline
        ]
        outline_points = chaikin(leaned, iterations=2)
        count = len(outline_points)
        centroid_x = sum(point[0] for point in outline_points) / count
        centroid_z = sum(point[1] for point in outline_points) / count

        front_points = []
        for x, z in outline_points:
            local_height = z - base_z
            if local_height < 0.045:
                surface = hair_top(x, front_y)
                if surface is not None and surface + 0.003 < z:
                    z = surface + 0.003
            front_points.append(Vector((x, front_y, z)))

        back_points = []
        for x, z in outline_points:
            bx = centroid_x + (x - centroid_x) * 0.92
            bz = centroid_z + (z - centroid_z) * 0.92
            local_height = bz - base_z
            if local_height < 0.045:
                surface = hair_top(bx, back_y)
                if surface is not None and surface + 0.003 < bz:
                    bz = surface + 0.003
            back_points.append(Vector((bx, back_y, bz)))

        x_min = min(point.x for point in front_points)
        x_max = max(point.x for point in front_points)
        z_min = min(point.z for point in front_points)
        z_max = max(point.z for point in front_points)
        vertices = front_points + back_points
        faces = [tuple(range(count)), tuple(range(2 * count - 1, count - 1, -1))]
        for index in range(count):
            nxt = (index + 1) % count
            faces.append((index, nxt, count + nxt, count + index))

        def outer_uv(point: Vector):
            return (
                min(1.0, max(0.0, (point.x - x_min) / max(1e-6, x_max - x_min))),
                min(1.0, max(0.0, (point.z - z_min) / max(1e-6, z_max - z_min))),
            )

        outer_obj = make_mesh(
            outer_name,
            vertices,
            faces,
            outer_material,
            armature,
            constant_weights({head_group: 1.0}),
            uv_fn=outer_uv,
            recalc=True,
        )
        bevel = outer_obj.modifiers.new("EarSoft", "BEVEL")
        bevel.width = 0.007
        bevel.segments = 2
        bpy.context.view_layer.objects.active = outer_obj
        for selected in bpy.context.selected_objects:
            selected.select_set(False)
        outer_obj.select_set(True)
        bpy.ops.object.modifier_move_to_index(modifier=bevel.name, index=0)
        bpy.ops.object.modifier_apply(modifier=bevel.name)
        outer_obj.select_set(False)

        inner_points = []
        for x, z in outline_points:
            inner_points.append(
                Vector(
                    (
                        centroid_x + (x - centroid_x) * 0.80,
                        front_y - 0.007,
                        centroid_z + (z - centroid_z) * 0.80 + 0.004,
                    )
                )
            )
        make_mesh(
            inner_name,
            inner_points,
            [tuple(range(count))],
            inner_material,
            armature,
            constant_weights({head_group: 1.0}),
            uv_fn=lambda point: (
                0.5,
                min(1.0, max(0.0, (point.z - z_min) / max(1e-6, z_max - z_min))),
            ),
        )
        print(f"EAR_REBUILT {side} width={x_max - x_min:.3f} height={z_max - z_min:.3f}")

    band_path = []
    for index in range(21):
        x = -0.145 + 0.290 * index / 20
        y = -0.055
        surface = hair_top(x, y)
        z = (surface + 0.004) if surface is not None else 1.10
        band_path.append(Vector((x, y, z)))
    band_vertices, band_faces = make_tube(band_path, [0.008] * len(band_path), segments=8, closed=False)
    make_mesh(
        "EarHeadband",
        band_vertices,
        band_faces,
        band_material,
        armature,
        constant_weights({"J_Bip_C_Head": 1.0}),
        recalc=True,
    )
    for sign, side in ((1, "L"), (-1, "R")):
        end = band_path[0] if sign < 0 else band_path[-1]
        connector_path = []
        for index in range(5):
            t = index / 4
            x = end.x + (sign * 0.180 - end.x) * t
            y = end.y + (0.040 - end.y) * t
            surface = hair_top(x, y)
            z = (surface + 0.004) if surface is not None else end.z + (1.10 - end.z) * t
            connector_path.append(Vector((x, y, z)))
        vertices, faces = make_tube(connector_path, [0.007] * len(connector_path), segments=8, closed=False)
        make_mesh(
            f"EarHeadbandSide{side}",
            vertices,
            faces,
            band_material,
            armature,
            constant_weights({"J_Bip_C_Head": 1.0}),
            recalc=True,
        )
    print("EAR_HEADBAND_DONE")


def upgrade_ear_inner(ear_material) -> None:
    for name in ("CatEarInnerL", "CatEarInnerR"):
        obj = bpy.data.objects.get(name)
        if not obj:
            print(f"EAR_MISSING {name}")
            continue
        obj.data.materials.clear()
        obj.data.materials.append(ear_material)
        zs = [(obj.matrix_world @ vertex.co).z for vertex in obj.data.vertices]
        z_min, z_max = min(zs), max(zs)
        layer = obj.data.uv_layers.get("UVMap")
        if not layer:
            layer = obj.data.uv_layers.new(name="UVMap")
        for polygon in obj.data.polygons:
            for loop_index in polygon.loop_indices:
                vertex_index = obj.data.loops[loop_index].vertex_index
                z = (obj.matrix_world @ obj.data.vertices[vertex_index].co).z
                v = (z - z_min) / max(1e-6, z_max - z_min)
                layer.data[loop_index].uv = (0.5, v)
        print(f"EAR_GRADIENT {name} z=({z_min:.3f},{z_max:.3f})")


# ---------------------------------------------------------------------------
# Phase 1.4 refinements: straight calves, thicker hands, relaxed curled rest hands
# ---------------------------------------------------------------------------


DEFAULT_FINGER_CURL_DEG: dict[str, tuple[float, float, float]] = {
    "Index": (6.0, 9.0, 7.0),
    "Middle": (7.5, 11.0, 8.5),
    "Ring": (9.5, 13.0, 10.0),
    "Little": (11.5, 15.0, 11.5),
}


def _skin_vertex_indices(body) -> set[int]:
    return {
        vi
        for poly in body.data.polygons
        if poly.material_index == 0
        for vi in poly.vertices
    }


def _vertex_group_weight(vertex, group_index: int | None) -> float:
    if group_index is None:
        return 0.0
    for group in vertex.groups:
        if group.group == group_index:
            return float(group.weight)
    return 0.0


def _palm_frame(body, skin_verts: set[int], side: str) -> tuple[list[int], Vector, Vector]:
    """Return (core_vertex_indices, palm_center_world, dorsal_palm_normal)."""
    hand_vg = body.vertex_groups.get(f"J_Bip_{side}_Hand")
    if hand_vg is None:
        raise SystemExit(f"缺少顶点组 J_Bip_{side}_Hand")
    mat = body.matrix_world
    core_indices: list[int] = []
    core_pts: list[list[float]] = []
    for vi in skin_verts:
        v = body.data.vertices[vi]
        if _vertex_group_weight(v, hand_vg.index) <= 0.5:
            continue
        w = mat @ v.co
        if w.y > -0.045:
            core_indices.append(vi)
            core_pts.append([w.x, w.y, w.z])
    if len(core_pts) < 12:
        raise SystemExit("手掌核心顶点采样异常")
    arr = np.array(core_pts, dtype=float)
    center = Vector(arr.mean(axis=0).tolist())
    _eigvals, eigvecs = np.linalg.eigh(np.cov(arr.T))
    normal = Vector(eigvecs[:, 0].tolist()).normalized()
    # Enforce dorsal direction: right hand (-X) points -X, left hand (+X) points +X.
    if (side == "R" and normal.x > 0.0) or (side == "L" and normal.x < 0.0):
        normal = -normal
    return core_indices, center, normal


def slim_calves(
    body,
    z_min: float = 0.075,
    z_max: float = 0.355,
    calf_peak_z: float = 0.230,
    max_width_shrink: float = 0.22,
    max_back_flatten: float = 0.72,
    max_front_trim: float = 0.25,
    center_shift_y: float = -0.008,
) -> dict[str, float]:
    """Straighten and slim the calves between ankle and knee with C1-smooth falloff."""
    skin_verts = _skin_vertex_indices(body)
    mat = body.matrix_world
    inv_mat = mat.inverted()
    metrics: dict[str, float] = {}

    for side, sign in (("L", 1.0), ("R", -1.0)):
        lo_pts: list[Vector] = []
        hi_pts: list[Vector] = []
        target_verts: list[tuple[int, Vector]] = []
        before_slice: list[Vector] = []

        for vi in skin_verts:
            w = mat @ body.data.vertices[vi].co
            if w.x * sign <= 0.01 or abs(w.y) >= 0.15:
                continue
            if 0.082 <= w.z <= 0.098:
                lo_pts.append(w)
            if 0.322 <= w.z <= 0.342:
                hi_pts.append(w)
            if 0.22 <= w.z <= 0.26:
                before_slice.append(w)
            if z_min < w.z < z_max:
                target_verts.append((vi, w))

        if len(lo_pts) < 4 or len(hi_pts) < 4:
            raise SystemExit("小腿锚点采样不足，无法执行直腿塑形")

        cx_lo = sum(p.x for p in lo_pts) / len(lo_pts)
        cy_lo = sum(p.y for p in lo_pts) / len(lo_pts)
        y_back_lo = max(p.y for p in lo_pts)
        cx_hi = sum(p.x for p in hi_pts) / len(hi_pts)
        cy_hi = sum(p.y for p in hi_pts) / len(hi_pts)
        y_back_hi = max(p.y for p in hi_pts)

        if before_slice:
            metrics[f"{side}_wx_before"] = max(p.x for p in before_slice) - min(p.x for p in before_slice)
            metrics[f"{side}_dy_before"] = max(p.y for p in before_slice) - min(p.y for p in before_slice)
            metrics[f"{side}_yback_before"] = max(p.y for p in before_slice)

        for vi, w in target_verts:
            z = w.z
            t = min(1.0, max(0.0, (z - 0.090) / (0.330 - 0.090)))
            cx = cx_lo + (cx_hi - cx_lo) * t
            cy = cy_lo + (cy_hi - cy_lo) * t
            y_back_line = y_back_lo + (y_back_hi - y_back_lo) * t

            edge_env = smoothstep((z - z_min) / 0.045) * smoothstep((z_max - z) / 0.050)
            bell = math.exp(-(((z - calf_peak_z) / 0.068) ** 2))
            weight = edge_env * bell

            new_x = cx + (w.x - cx) * (1.0 - max_width_shrink * weight)
            shifted_y = w.y + center_shift_y * weight
            if shifted_y > y_back_line:
                excess = shifted_y - y_back_line
                new_y = y_back_line + excess * (1.0 - max_back_flatten * edge_env)
            elif shifted_y < cy:
                new_y = cy + (shifted_y - cy) * (1.0 - max_front_trim * weight)
            else:
                new_y = shifted_y

            body.data.vertices[vi].co = inv_mat @ Vector((new_x, new_y, z))

        after_slice = [
            mat @ body.data.vertices[vi].co
            for vi, _ in target_verts
            if 0.22 <= (mat @ body.data.vertices[vi].co).z <= 0.26
        ]
        if after_slice:
            metrics[f"{side}_wx_after"] = max(p.x for p in after_slice) - min(p.x for p in after_slice)
            metrics[f"{side}_dy_after"] = max(p.y for p in after_slice) - min(p.y for p in after_slice)
            metrics[f"{side}_yback_after"] = max(p.y for p in after_slice)

    body.data.update()
    print(
        "CALVES_SLIMMED "
        f"L_wx={metrics.get('L_wx_before', 0.0):.4f}->{metrics.get('L_wx_after', 0.0):.4f} "
        f"L_dy={metrics.get('L_dy_before', 0.0):.4f}->{metrics.get('L_dy_after', 0.0):.4f} "
        f"L_yback={metrics.get('L_yback_before', 0.0):.4f}->{metrics.get('L_yback_after', 0.0):.4f} "
        f"R_wx={metrics.get('R_wx_before', 0.0):.4f}->{metrics.get('R_wx_after', 0.0):.4f} "
        f"R_dy={metrics.get('R_dy_before', 0.0):.4f}->{metrics.get('R_dy_after', 0.0):.4f} "
        f"R_yback={metrics.get('R_yback_before', 0.0):.4f}->{metrics.get('R_yback_after', 0.0):.4f}"
    )
    return metrics


def thicken_hands(
    armature,
    body,
    dorsal_scale: float = 1.56,
    palmar_scale: float = 1.44,
    proximal_finger_scale: float = 1.28,
    distal_finger_scale: float = 1.16,
    thumb_scale: float = 1.22,
) -> dict[str, float]:
    """Thicken flattened palms and fingers along the palm normal while tapering to 1.0x at the wrist."""
    _ = armature
    skin_verts = _skin_vertex_indices(body)
    mat = body.matrix_world
    inv_mat = mat.inverted()
    vg_index = {vg.name: vg.index for vg in body.vertex_groups}
    metrics: dict[str, float] = {}

    for side in ("R", "L"):
        core_indices, palm_center, palm_normal = _palm_frame(body, skin_verts, side)
        core_proj_before = np.array(
            [(mat @ body.data.vertices[vi].co).dot(palm_normal) for vi in core_indices],
            dtype=float,
        )
        thick_before = float(np.ptp(core_proj_before))
        if thick_before < 0.005:
            raise SystemExit("手掌核心顶点采样异常")
        metrics[f"{side}_thick_before"] = thick_before

        hand_idx = vg_index.get(f"J_Bip_{side}_Hand")
        arm_idx = vg_index.get(f"J_Bip_{side}_LowerArm")
        p1_indices = [
            vg_index[f"J_Bip_{side}_{finger}1"]
            for finger in ("Index", "Middle", "Ring", "Little")
            if f"J_Bip_{side}_{finger}1" in vg_index
        ]
        p23_indices = [
            vg_index[f"J_Bip_{side}_{finger}{seg}"]
            for finger in ("Index", "Middle", "Ring", "Little")
            for seg in (2, 3)
            if f"J_Bip_{side}_{finger}{seg}" in vg_index
        ]
        thumb_indices = [
            vg_index[f"J_Bip_{side}_Thumb{seg}"]
            for seg in (1, 2, 3)
            if f"J_Bip_{side}_Thumb{seg}" in vg_index
        ]
        all_phalanx_indices = p1_indices + p23_indices + thumb_indices

        # Local midplane projection per phalanx so fingers/thumbs thicken symmetrically
        # without shifting sideways relative to the palm.
        d_palm = float(palm_center.dot(palm_normal))
        d_by_group: dict[int, float] = {}
        for gidx in all_phalanx_indices:
            pts = [
                (mat @ body.data.vertices[vi].co).dot(palm_normal)
                for vi in skin_verts
                if _vertex_group_weight(body.data.vertices[vi], gidx) > 0.5
            ]
            if pts:
                d_by_group[gidx] = float(sum(pts) / len(pts))

        p1_set = set(p1_indices)
        p23_set = set(p23_indices)
        thumb_set = set(thumb_indices)

        for vi in skin_verts:
            v = body.data.vertices[vi]
            w_hand = 0.0
            w_arm = 0.0
            w_p1 = 0.0
            w_p23 = 0.0
            w_thumb = 0.0
            phalanx_w: list[tuple[int, float]] = []
            thumb_w: list[tuple[int, float]] = []

            for g in v.groups:
                gi = g.group
                gw = float(g.weight)
                if gw <= 0.0:
                    continue
                if gi == hand_idx:
                    w_hand += gw
                elif gi == arm_idx:
                    w_arm += gw
                elif gi in p1_set:
                    w_p1 += gw
                    phalanx_w.append((gi, gw))
                elif gi in p23_set:
                    w_p23 += gw
                    phalanx_w.append((gi, gw))
                elif gi in thumb_set:
                    w_thumb += gw
                    thumb_w.append((gi, gw))

            active_w = w_hand + w_p1 + w_p23 + w_thumb
            if active_w <= 0.01:
                continue

            if w_thumb > 0.5 and thumb_w:
                tw_sum = sum(gw for gi, gw in thumb_w if gi in d_by_group)
                d_ref = (
                    sum(d_by_group[gi] * gw for gi, gw in thumb_w if gi in d_by_group) / tw_sum
                    if tw_sum > 1e-6
                    else d_palm
                )
            else:
                num = w_hand * d_palm
                den = w_hand
                for gi, gw in phalanx_w + thumb_w:
                    if gi in d_by_group:
                        num += d_by_group[gi] * gw
                        den += gw
                d_ref = num / den if den > 1e-6 else d_palm

            w_pos = mat @ v.co
            signed_d = float(w_pos.dot(palm_normal)) - d_ref
            hand_s = dorsal_scale if signed_d >= 0.0 else palmar_scale
            total_w = active_w + w_arm
            target_scale = (
                w_hand * hand_s
                + w_p1 * proximal_finger_scale
                + w_p23 * distal_finger_scale
                + w_thumb * thumb_scale
                + w_arm * 1.0
            ) / total_w
            new_world = w_pos + palm_normal * (signed_d * (target_scale - 1.0))
            v.co = inv_mat @ new_world

        core_proj_after = np.array(
            [(mat @ body.data.vertices[vi].co).dot(palm_normal) for vi in core_indices],
            dtype=float,
        )
        metrics[f"{side}_thick_after"] = float(np.ptp(core_proj_after))

    body.data.update()
    print(
        "HANDS_THICKENED "
        f"L={metrics.get('L_thick_before', 0.0):.4f}->{metrics.get('L_thick_after', 0.0):.4f} "
        f"R={metrics.get('R_thick_before', 0.0):.4f}->{metrics.get('R_thick_after', 0.0):.4f}"
    )
    return metrics


def curl_rest_hands(
    armature,
    body,
    finger_angles_deg: dict[str, tuple[float, float, float]] | None = None,
    thumb_angles_deg: tuple[float, float] = (8.0, 12.0),
) -> dict[str, float]:
    """Bake a natural relaxed finger curl into Body rest geometry around anatomical joints.

    Avoids Pose-Mode armature_apply on the inverted/offset VRM finger bones so
    skeletonRestPoses and all 8 action clips remain 100% compatible.
    """
    _ = armature
    angles_map = finger_angles_deg or DEFAULT_FINGER_CURL_DEG
    skin_verts = _skin_vertex_indices(body)
    mat = body.matrix_world
    inv_mat = mat.inverted()
    vg_index = {vg.name: vg.index for vg in body.vertex_groups}
    band = 0.008
    metrics: dict[str, float] = {}

    def group_verts_world(group_name: str) -> list[tuple[int, Vector]]:
        gidx = vg_index.get(group_name)
        if gidx is None:
            return []
        result: list[tuple[int, Vector]] = []
        for vi in skin_verts:
            v = body.data.vertices[vi]
            if _vertex_group_weight(v, gidx) > 0.5:
                result.append((vi, mat @ v.co))
        return result

    def centroid(pts: list[tuple[int, Vector]]) -> Vector:
        total = Vector((0.0, 0.0, 0.0))
        for _, p in pts:
            total += p
        return total / max(1, len(pts))

    for side in ("R", "L"):
        _core_idx, palm_center, palm_normal = _palm_frame(body, skin_verts, side)
        mid2_pts = group_verts_world(f"J_Bip_{side}_Middle2")
        if not mid2_pts:
            raise SystemExit(f"缺少 J_Bip_{side}_Middle2 顶点，无法弯曲手指")
        finger_dir = (centroid(mid2_pts) - palm_center).normalized()
        bend_axis = finger_dir.cross(palm_normal).normalized()
        if ((Matrix.Rotation(0.1, 3, bend_axis) @ finger_dir) - finger_dir).dot(-palm_normal) <= 0.0:
            bend_axis = -bend_axis

        index_vert_ids: set[int] = set()
        index1_center: Vector | None = None

        for finger in ("Index", "Middle", "Ring", "Little"):
            a1, a2, a3 = angles_map[finger]
            g1_name = f"J_Bip_{side}_{finger}1"
            g2_name = f"J_Bip_{side}_{finger}2"
            g3_name = f"J_Bip_{side}_{finger}3"
            pts1 = group_verts_world(g1_name)
            pts2 = group_verts_world(g2_name)
            pts3 = group_verts_world(g3_name)
            if not pts1 or not pts2 or not pts3:
                raise SystemExit(f"缺少 {side}_{finger} 指节顶点")

            c1 = centroid(pts1)
            c2 = centroid(pts2)
            c3 = centroid(pts3)
            if finger == "Index":
                index1_center = c1.copy()

            proj1 = np.array([p.dot(finger_dir) for _, p in pts1], dtype=float)
            q15 = float(np.quantile(proj1, 0.15))
            p_mcp = c1 + finger_dir * (q15 - c1.dot(finger_dir))
            p_pip = (c1 + c2) * 0.5
            p_dip = (c2 + c3) * 0.5

            len_before = (c3 - p_mcp).length
            c3_before = c3.copy()

            g1_idx = vg_index[g1_name]
            g2_idx = vg_index[g2_name]
            g3_idx = vg_index[g3_name]
            d_mcp = p_mcp.dot(finger_dir)
            d_pip = p_pip.dot(finger_dir)
            d_dip = p_dip.dot(finger_dir)

            for vi in skin_verts:
                v = body.data.vertices[vi]
                w_f = (
                    _vertex_group_weight(v, g1_idx)
                    + _vertex_group_weight(v, g2_idx)
                    + _vertex_group_weight(v, g3_idx)
                )
                if w_f <= 0.01:
                    continue
                if finger == "Index":
                    index_vert_ids.add(vi)
                w_pos = mat @ v.co
                proj = w_pos.dot(finger_dir)
                s1 = smoothstep((proj - (d_mcp - band * 0.5)) / band) * min(1.0, w_f)
                s2 = smoothstep((proj - (d_pip - band * 0.5)) / band) * min(1.0, w_f)
                s3 = smoothstep((proj - (d_dip - band * 0.5)) / band) * min(1.0, w_f)

                # Forward-kinematics order (DIP -> PIP -> MCP) keeps segment lengths rigid.
                p = w_pos.copy()
                for pivot, ang_deg, s in ((p_dip, a3, s3), (p_pip, a2, s2), (p_mcp, a1, s1)):
                    if s > 1e-6:
                        rot = Matrix.Rotation(math.radians(ang_deg * s), 3, bend_axis)
                        p = pivot + rot @ (p - pivot)
                v.co = inv_mat @ p

            c3_after = centroid([(vi, mat @ body.data.vertices[vi].co) for vi, _ in pts3])
            palmar_disp = float((c3_after - c3_before).dot(-palm_normal))
            len_after = (c3_after - p_mcp).length
            len_change = abs(len_after - len_before) / max(len_before, 1e-6)
            metrics[f"{side}_{finger}_palmar_disp"] = palmar_disp
            metrics[f"{side}_{finger}_len_change"] = len_change
            if palmar_disp <= 0.0 or len_change > 0.10:
                raise SystemExit(
                    f"静置手型弯曲方向或长度畸变: {side}_{finger} disp={palmar_disp:.4f} len_change={len_change:.4f}"
                )

        # Gentle inward thumb curl toward palm & index side.
        t1_name = f"J_Bip_{side}_Thumb1"
        t2_name = f"J_Bip_{side}_Thumb2"
        t3_name = f"J_Bip_{side}_Thumb3"
        tpts1 = group_verts_world(t1_name)
        tpts2 = group_verts_world(t2_name)
        tpts3 = group_verts_world(t3_name)
        if not tpts1 or not tpts2 or not tpts3 or index1_center is None:
            raise SystemExit(f"缺少 {side}_Thumb 顶点")

        tc1 = centroid(tpts1)
        tc2 = centroid(tpts2)
        tc3 = centroid(tpts3)
        p_t2 = (tc1 + tc2) * 0.5
        p_t3 = (tc2 + tc3) * 0.5
        thumb_dir = (tc3 - tc1).normalized()
        inward = ((-palm_normal) * 0.70 + (index1_center - tc3).normalized() * 0.30).normalized()
        thumb_axis = thumb_dir.cross(inward).normalized()
        if ((Matrix.Rotation(0.1, 3, thumb_axis) @ thumb_dir) - thumb_dir).dot(inward) <= 0.0:
            thumb_axis = -thumb_axis

        t1_idx = vg_index[t1_name]
        t2_idx = vg_index[t2_name]
        t3_idx = vg_index[t3_name]
        d_t2 = p_t2.dot(thumb_dir)
        d_t3 = p_t3.dot(thumb_dir)
        tc3_before = tc3.copy()
        ta1, ta2 = thumb_angles_deg

        for vi in skin_verts:
            v = body.data.vertices[vi]
            w_t = (
                _vertex_group_weight(v, t1_idx)
                + _vertex_group_weight(v, t2_idx)
                + _vertex_group_weight(v, t3_idx)
            )
            if w_t <= 0.01:
                continue
            w_pos = mat @ v.co
            proj = w_pos.dot(thumb_dir)
            s_t2 = smoothstep((proj - (d_t2 - band * 0.5)) / band) * min(1.0, w_t)
            s_t3 = smoothstep((proj - (d_t3 - band * 0.5)) / band) * min(1.0, w_t)
            p = w_pos.copy()
            for pivot, ang_deg, s in ((p_t3, ta2, s_t3), (p_t2, ta1, s_t2)):
                if s > 1e-6:
                    rot = Matrix.Rotation(math.radians(ang_deg * s), 3, thumb_axis)
                    p = pivot + rot @ (p - pivot)
            v.co = inv_mat @ p

        tc3_after = centroid([(vi, mat @ body.data.vertices[vi].co) for vi, _ in tpts3])
        thumb_disp = float((tc3_after - tc3_before).dot(-palm_normal))
        metrics[f"{side}_Thumb_palmar_disp"] = thumb_disp

        # Verify Thumb3 does not collide with Index.
        thumb3_world = [mat @ body.data.vertices[vi].co for vi, _ in tpts3]
        index_world = [mat @ body.data.vertices[vi].co for vi in index_vert_ids]
        min_thumb_index = min((tp - ip).length for tp in thumb3_world for ip in index_world)
        metrics[f"{side}_thumb_index_min_dist"] = min_thumb_index
        if thumb_disp <= 0.0 or min_thumb_index < 0.010:
            raise SystemExit(
                f"静置手型拇指弯曲异常或穿模: {side} disp={thumb_disp:.4f} min_dist={min_thumb_index:.4f}"
            )

    body.data.update()
    print(
        "HANDS_CURLED "
        f"R_idx={metrics['R_Index_palmar_disp']:.4f} R_lit={metrics['R_Little_palmar_disp']:.4f} "
        f"R_th={metrics['R_Thumb_palmar_disp']:.4f} R_ti={metrics['R_thumb_index_min_dist']:.4f} "
        f"L_idx={metrics['L_Index_palmar_disp']:.4f} L_lit={metrics['L_Little_palmar_disp']:.4f} "
        f"L_th={metrics['L_Thumb_palmar_disp']:.4f} L_ti={metrics['L_thumb_index_min_dist']:.4f}"
    )
    return metrics


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main() -> None:
    if not PHASE0_BLEND.exists():
        raise SystemExit(f"缺少 {PHASE0_BLEND}")
    OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    texture_paths = generate_textures()
    bpy.ops.wm.open_mainfile(filepath=str(PHASE0_BLEND))
    scene = bpy.context.scene
    armature = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    body = bpy.data.objects.get("Body")
    if not body:
        raise SystemExit("缺少 Body")

    for image in bpy.data.images:
        if image.name.startswith("gen_") and image.filepath:
            image.reload()

    raise_head(armature, 0.040)
    recenter_irises(armature, 0.005)
    bake_idle_mouth(bpy.data.objects.get("Face"), 0.15)
    reshape_ahoge()

    mouth_inner_path = ROOT / "textures" / "phase0" / "_01.png"
    if mouth_inner_path.exists():
        mouth_inner_image = load_image("MouthInnerTex", mouth_inner_path)
        mouth_material = bpy.data.materials.new("MouthInner")
        mouth_material.use_nodes = True
        nodes = mouth_material.node_tree.nodes
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = mouth_inner_image
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Metallic"].default_value = 0.0
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.0
        mouth_material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
        mouth_material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
        face = bpy.data.objects.get("Face")
        if face:
            face.material_slots[0].material = mouth_material
        print(f"MOUTH_INNER_TEXTURE {mouth_inner_image.name}")

    hoodie_image = load_image("HoodieGradientTex", texture_paths["hoodie"])
    shorts_image = load_image("SolidShortsTex", texture_paths["shorts"])
    trim_image = load_image("SolidTrimTex", texture_paths["trim"])
    rib_image = load_image("SolidRibTex", texture_paths["rib"])
    seam_image = load_image("SolidSeamTex", texture_paths["seam"])
    hoodfold_image = load_image("SolidHoodFoldTex", texture_paths["hoodfold"])
    neck_image = load_image("NeckSkinTex", texture_paths["neck"])
    headbandtop_image = load_image("HeadbandTopTex", texture_paths["headbandtop"])
    ear_image = load_image("EarInnerGradientTex", texture_paths["ear"])

    # Keep the VRM MToon shading (the approved look) and only swap the colour
    # textures.  Principled copies were blown out by the review lighting.
    tops_material = bpy.data.materials["N00_004_01_Tops_01_CLOTH"]
    bottoms_material = bpy.data.materials["N00_001_01_Bottoms_01_CLOTH"]
    replace_mtoon_images(tops_material, hoodie_image)
    replace_mtoon_images(bottoms_material, shorts_image)
    hoodie_material = tops_material
    shorts_material = bottoms_material
    trim_material = clone_mtoon(tops_material, "TrimWhite", trim_image)
    rib_material = clone_mtoon(tops_material, "HoodieRib", rib_image)
    seam_material = clone_mtoon(tops_material, "HoodieSeam", seam_image)
    hoodfold_material = clone_mtoon(tops_material, "HoodFold", hoodfold_image)
    body_skin_material = bpy.data.materials.get("N00_000_00_Body_00_SKIN", tops_material)
    neck_skin_material = clone_mtoon(body_skin_material, "NeckSkin", neck_image)
    headbandtop_material = clone_mtoon(tops_material, "HeadbandTop", headbandtop_image)
    # The drawstrings read as grey-blue under the scene light when they share
    # the hoodie's PBR material.  A pure white emissive material keeps them
    # white; emission is raised to 2.5x so tone mapping still resolves them as
    # white against the hoodie (plain emission 1.0 lands near the hoodie grey).
    string_material = make_emissive_color_material("DrawstringWhite", (1.0, 1.0, 1.0), intensity=2.5)
    sock_material = make_sock_white_material()
    ear_material = make_emissive_textured_material("EarInnerGradient", ear_image, strength=1.0)

    cut_shorts(armature, body)
    body.material_slots[2].material = shorts_material
    inflate_tops(body, 1.03)
    body.material_slots[3].material = hoodie_material
    set_tops_uvs(body)

    # Phase 1.4 geometry refinements must run before NearestSkinWeights and add_socks.
    slim_calves(body)
    thicken_hands(armature, body)
    curl_rest_hands(armature, body)

    nearest = NearestSkinWeights(body)
    add_shorts_hem_bands(armature, body, trim_material, nearest)
    add_socks(armature, body, nearest, sock_material)
    add_hoodie_hem(armature, hoodie_material, rib_material)
    add_sleeves(armature, nearest, hoodie_material, rib_material)
    add_pocket(armature, body, hoodie_material, seam_material)
    # The body neck skin follows the raised head; no separate neck cylinder
    # (it showed as a mismatched skin patch).
    add_v_neck(armature, body, neck_skin_material, hoodie_material, nearest)
    add_collar(armature, hoodie_material)
    add_hood(armature, hoodie_material, hoodfold_material, rib_material)
    add_drawstrings(armature, body, string_material, string_material)
    rebuild_cat_ears(armature, headbandtop_material)
    upgrade_ear_inner(ear_material)

    # Sync all 8 action clips from avatar_common.py (prevents stale phase0 actions).
    ranges = ac.make_actions(armature, 30)
    if armature.animation_data:
        armature.animation_data.action = None
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = max(ranges.values())
    print(f"ACTIONS {sorted(ranges)}")

    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), check_existing=False)
    print(f"SAVED {OUT_BLEND}")


main()
