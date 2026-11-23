"""Build the Phase 0 avatar: textures, proportions, cat ears, ahoge, hair clip.

Run:
    blender --background --factory-startup --python scripts/build_avatar.py

Output:
    work/phase0/minimate_phase0.blend

The Face mesh topology is never edited; shape keys are transformed in place,
so all 52 ARKit names remain intact.
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import avatar_common as ac  # noqa: E402

ROOT = SCRIPT_DIR.parent
CONFIG = ac.load_config()
OUT_BLEND = ROOT / "work" / "phase0" / "minimate_phase0.blend"
TEXTURE_DIR = ROOT / "textures" / "phase0"
BASE_TEXTURE_DIR = ROOT / "work" / "base" / "textures"


def armature_bone(armature, suffix: str):
    for bone in armature.data.bones:
        if bone.name.endswith(suffix):
            return bone
    raise SystemExit(f"找不到骨骼 {suffix}")


def head_related_bones(armature) -> set[str]:
    """Head subtree plus hair joints and eye-adjust bones."""
    head = armature_bone(armature, "Head")
    names: set[str] = set()

    def walk(bone):
        names.add(bone.name)
        for child in bone.children:
            walk(child)

    walk(head)
    for bone in armature.data.bones:
        if "HairJ" in bone.name or "HairJoint" in bone.name or bone.name.startswith("J_Adj_"):
            names.add(bone.name)
        if bone.name.endswith("Eye"):
            names.add(bone.name)
    return names


def object_transform(obj, armature):
    obj_to_arm = armature.matrix_world.inverted() @ obj.matrix_world
    return obj_to_arm, obj_to_arm.inverted()


def head_transform(point: Vector, pivot: Vector, scale: float) -> Vector:
    return pivot + (point - pivot) * scale


def body_transform(point: Vector, pivot: Vector, scale: float) -> Vector:
    return Vector((point.x, point.y, pivot.z + (point.z - pivot.z) * scale))


def arm_bones(armature) -> dict[str, tuple[set[str], Vector]]:
    result: dict[str, tuple[set[str], Vector]] = {}
    for side in ("L", "R"):
        names = set()
        for bone in armature.data.bones:
            if f"_Bip_{side}_" not in bone.name:
                continue
            if any(token in bone.name for token in ("UpperArm", "LowerArm", "Hand", "Index", "Middle", "Ring", "Little", "Thumb")):
                names.add(bone.name)
        upper = armature_bone(armature, f"{side}_UpperArm")
        result[side] = (names, upper.head_local.copy())
    return result


def vertex_weight_sum(obj, vertex, names: set[str]) -> float:
    group_names = {group.index: group.name for group in obj.vertex_groups}
    total = 0.0
    for element in vertex.groups:
        if group_names.get(element.group) in names:
            total += element.weight
    return max(0.0, min(1.0, total))


def vertex_head_weight(obj, vertex, head_names: set[str]) -> float:
    group_names = {group.index: group.name for group in obj.vertex_groups}
    weight = 0.0
    for element in vertex.groups:
        name = group_names.get(element.group)
        if name in head_names:
            weight += element.weight
    return max(0.0, min(1.0, weight))


def scale_meshes(armature, head_names: set[str], pivot: Vector, head_scale: float, body_scale: float, body_width_scale: float, arm_scale: float) -> None:
    arm_map = arm_bones(armature)
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        obj_to_arm, arm_to_obj = object_transform(obj, armature)

        if obj.name == "Face" or obj.name == "Hair001":
            if obj.data.shape_keys:
                for key in obj.data.shape_keys.key_blocks:
                    for i, point in enumerate(key.data):
                        arm_point = obj_to_arm @ point.co
                        key.data[i].co = arm_to_obj @ head_transform(arm_point, pivot, head_scale)
            else:
                for vertex in obj.data.vertices:
                    arm_point = obj_to_arm @ vertex.co
                    vertex.co = arm_to_obj @ head_transform(arm_point, pivot, head_scale)
            print(f"SCALED_HEAD {obj.name} full")
            continue

        if obj.data.shape_keys:
            raise SystemExit(f"未预期的形态键网格: {obj.name}")

        for vertex in obj.data.vertices:
            arm_point = obj_to_arm @ vertex.co
            weight = vertex_head_weight(obj, vertex, head_names)
            head_point = head_transform(arm_point, pivot, head_scale)
            body_point = body_transform(arm_point, pivot, body_scale)
            body_point.x *= body_width_scale
            body_point.y *= body_width_scale
            for side, (names, original_pivot) in arm_map.items():
                arm_weight = vertex_weight_sum(obj, vertex, names)
                if arm_weight <= 0:
                    continue
                arm_pivot = body_transform(original_pivot, pivot, body_scale)
                arm_pivot.x *= body_width_scale
                arm_pivot.y *= body_width_scale
                body_point.x = arm_pivot.x + (body_point.x - arm_pivot.x) * (
                    1.0 + (arm_scale - 1.0) * arm_weight
                )
            vertex.co = arm_to_obj @ (head_point * weight + body_point * (1.0 - weight))
        print(f"SCALED_MIXED {obj.name}")


def scale_bones(armature, head_names: set[str], pivot: Vector, head_scale: float, body_scale: float, body_width_scale: float, arm_scale: float) -> None:
    arm_map = arm_bones(armature)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in armature.data.edit_bones:
        if bone.name in head_names:
            bone.head = head_transform(bone.head, pivot, head_scale)
            bone.tail = head_transform(bone.tail, pivot, head_scale)
        else:
            bone.head = body_transform(bone.head, pivot, body_scale)
            bone.tail = body_transform(bone.tail, pivot, body_scale)
            bone.head.x *= body_width_scale
            bone.tail.x *= body_width_scale
            bone.head.y *= body_width_scale
            bone.tail.y *= body_width_scale
    for side, (names, original_pivot) in arm_map.items():
        arm_pivot = body_transform(original_pivot, pivot, body_scale)
        arm_pivot.x *= body_width_scale
        arm_pivot.y *= body_width_scale
        for bone in armature.data.edit_bones:
            if bone.name not in names:
                continue
            bone.head.x = arm_pivot.x + (bone.head.x - arm_pivot.x) * arm_scale
            bone.tail.x = arm_pivot.x + (bone.tail.x - arm_pivot.x) * arm_scale
    bpy.ops.object.mode_set(mode="OBJECT")
    print("SCALED_BONES")


def apply_a_pose(armature, body_obj, angle: float = -1.1) -> None:
    """Bake a relaxed A-pose into the Body mesh and the armature rest pose."""
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    for side in ("L", "R"):
        bone = armature.pose.bones.get(f"J_Bip_{side}_UpperArm")
        if not bone:
            continue
        bone.rotation_mode = "XYZ"
        bone.rotation_euler = (angle, 0.0, 0.0)
    bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")

    # Bake the arm deformation into the Body mesh (no shape keys on Body).
    bpy.ops.object.select_all(action="DESELECT")
    body_obj.select_set(True)
    bpy.context.view_layer.objects.active = body_obj
    for modifier in list(body_obj.modifiers):
        if modifier.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
            break

    # Make the A-pose the armature rest pose, then re-attach the modifier.
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    modifier = body_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    print("A_POSE_BAKED")


def replace_textures() -> dict[str, bpy.types.Image]:
    images: dict[str, bpy.types.Image] = {}
    for path in sorted(TEXTURE_DIR.glob("*.png")):
        image = bpy.data.images.load(str(path.resolve()))
        image.name = f"gen_{path.stem}"
        images[path.stem] = image
    for material in bpy.data.materials:
        if not material.use_nodes or not material.node_tree:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image and node.image.name in images:
                node.image = images[node.image.name]
    print(f"TEXTURES_REPLACED {sorted(images)}")
    return images


def srgb_to_linear(color: tuple[float, float, float]) -> tuple[float, float, float]:
    def convert(value: float) -> float:
        return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4

    return tuple(convert(value) for value in color)


def hex_rgb(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) / 255.0 for i in (0, 2, 4))


def make_solid_material(name: str, hex_value: str, roughness: float = 0.65, emission: float = 0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    color = srgb_to_linear(hex_rgb(hex_value))
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission > 0:
        bsdf.inputs["Emission Color"].default_value = (*color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_textured_material(name: str, image: bpy.types.Image, roughness: float = 0.65):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.node_tree.nodes.clear()
    output = material.node_tree.nodes.new("ShaderNodeOutputMaterial")
    bsdf = material.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def make_emissive_textured_material(name: str, image):
    """Unlit-ish textured material: emission only, so a thin ahoge is not blown out."""
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
    bsdf.inputs["Emission Strength"].default_value = 1.0
    material.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


def bind_to_head(obj, armature, head_bone_name: str) -> None:
    obj.parent = armature
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = armature
    group = obj.vertex_groups.new(name=head_bone_name)
    group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")


def planar_uv(obj, bounds=None) -> None:
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    uv_layer = obj.data.uv_layers.active
    coords = [vertex.co.copy() for vertex in obj.data.vertices]
    if bounds is None:
        min_x = min(point.x for point in coords)
        max_x = max(point.x for point in coords)
        min_z = min(point.z for point in coords)
        max_z = max(point.z for point in coords)
    else:
        min_x, max_x, min_z, max_z = bounds
    width = max(max_x - min_x, 1e-6)
    height = max(max_z - min_z, 1e-6)
    for loop in obj.data.loops:
        point = obj.data.vertices[loop.vertex_index].co
        uv = ((point.x - min_x) / width, (point.z - min_z) / height)
        uv_layer.data[loop.index].uv = uv


def make_mesh(name: str, vertices, faces, material, armature, head_bone_name: str):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bind_to_head(obj, armature, head_bone_name)
    return obj


def make_ear_prism(name: str, side: int, half_width: float, top: float, head_height: float, material, armature, head_bone_name: str):
    points = [
        (0.26 * half_width, top - 0.26 * head_height),
        (0.92 * half_width, top - 0.22 * head_height),
        (0.90 * half_width, top + 0.02 * head_height),
        (0.70 * half_width, top + 0.19 * head_height),
        (0.29 * half_width, top - 0.01 * head_height),
    ]
    y_front, y_back = -0.045, 0.035
    count = len(points)
    vertices = []
    for x, z in points:
        vertices.append((side * x, y_front, z))
    for x, z in points:
        vertices.append((side * x, y_back, z))
    faces = [tuple(range(count)), tuple(range(2 * count - 1, count - 1, -1))]
    for i in range(count):
        nxt = (i + 1) % count
        faces.append((i, nxt, count + nxt, count + i))
    obj = make_mesh(name, vertices, faces, material, armature, head_bone_name)
    planar_uv(obj)
    return obj


def make_ear_inner(name: str, side: int, half_width: float, top: float, head_height: float, material, armature, head_bone_name: str):
    points = [
        (0.36 * half_width, top - 0.22 * head_height),
        (0.84 * half_width, top - 0.18 * head_height),
        (0.83 * half_width, top + 0.00 * head_height),
        (0.70 * half_width, top + 0.14 * head_height),
        (0.38 * half_width, top - 0.02 * head_height),
    ]
    vertices = [(side * x, -0.055, z) for x, z in points]
    faces = [tuple(range(len(points)))]
    obj = make_mesh(name, vertices, faces, material, armature, head_bone_name)
    planar_uv(obj)
    return obj


def make_tube(name: str, points: list[Vector], radii: list[float], material, armature, head_bone_name: str, segments: int = 8):
    rings = []
    for index, point in enumerate(points):
        if index == 0:
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
    return make_mesh(name, vertices, faces, material, armature, head_bone_name)


def map_tube_uv(obj, ring_count: int, segments: int, v_start: float, v_end: float, u: float = 0.5) -> None:
    """Map a tube's rings onto a vertical strip of the hair texture."""
    uv_layer = obj.data.uv_layers.new(name="UVMap")
    for loop in obj.data.loops:
        ring = loop.vertex_index // segments
        t = ring / max(ring_count - 1, 1)
        uv_layer.data[loop.index].uv = (u, v_start + (v_end - v_start) * t)


def make_rounded_box(name: str, location, scale, material, armature, head_bone_name: str, bevel: float = 0.008):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    box = bpy.context.object
    box.name = name
    box.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    modifier = box.modifiers.new("Bevel", "BEVEL")
    modifier.width = bevel
    modifier.segments = 3
    bpy.context.view_layer.objects.active = box
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    box.data.materials.append(material)
    bind_to_head(box, armature, head_bone_name)
    return box


def make_hair_decal(name: str, sign: int, half_width: float, side_z: float,
                    width_y: float, height_z: float, x_offset: float, shrink_offset: float,
                    material, armature, head_bone_name: str, hair_obj, y_center: float = 0.0):
    """Small grid that shrinkwraps onto the hair surface (no protruding box)."""
    xs = sign * (half_width + x_offset)
    ys = [y_center - width_y / 2, y_center, y_center + width_y / 2]
    zs = [side_z - height_z / 2, side_z, side_z + height_z / 2]
    vertices = [(xs, y, z) for z in zs for y in ys]
    faces = []
    for row in range(2):
        for col in range(2):
            a = row * 3 + col
            faces.append((a, a + 1, a + 4, a + 3))
    obj = make_mesh(name, vertices, faces, material, armature, head_bone_name)
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new("Shrinkwrap", "SHRINKWRAP")
    modifier.target = hair_obj
    modifier.wrap_method = "NEAREST_SURFACEPOINT"
    modifier.offset = shrink_offset
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def make_headband(armature, head_bone_name: str, half_width: float, top: float, head_height: float,
                  band_material, side_material, accent_material):
    """Cat-ear headband: a thin arc over the head plus the visible side connectors.

    The white/blue rectangle at the temple in the design is the side of this
    headband, not a separate hair clip.
    """
    side_z = top - 0.30 * head_height
    center_z = top - 0.06 * head_height
    points = []
    for step in range(17):
        t = -1.0 + 2.0 * step / 16.0
        x = t * half_width * 0.90
        z = side_z + (center_z - side_z) * (1.0 - t * t)
        points.append(Vector((x, 0.04, z)))
    hair_obj = bpy.data.objects.get("Hair001")
    if hair_obj:
        # Only the character's right side piece is visible in the design front view.
        make_hair_decal(
            "HeadbandSideL", -1, half_width, side_z,
            0.050, 0.060, 0.0, 0.002, side_material, armature, head_bone_name, hair_obj, 0.030,
        )
        make_hair_decal(
            "HeadbandAccentL", -1, half_width, side_z,
            0.018, 0.022, 0.002, 0.004, accent_material, armature, head_bone_name, hair_obj, 0.030,
        )


def main() -> None:
    vrm_path = (ROOT / CONFIG["source"]["vrm"]).resolve()
    if not vrm_path.exists():
        raise SystemExit(f"底座 VRM 不存在: {vrm_path}")
    OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    ac.enable_vrm_addon()
    bpy.ops.import_scene.vrm(filepath=str(vrm_path))

    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    head_bone = armature_bone(armature, "Head")
    head_bone_name = head_bone.name
    pivot = head_bone.head_local.copy()
    head_scale = float(CONFIG["proportions"]["headScale"])
    body_scale = float(CONFIG["proportions"]["bodyScale"])
    body_width_scale = float(CONFIG["proportions"].get("bodyWidthScale", 1.0))
    arm_scale = float(CONFIG["proportions"].get("armLengthScale", 1.0))
    head_names = head_related_bones(armature)
    print(f"HEAD_BONES {len(head_names)} pivot={tuple(round(v, 4) for v in pivot)}")

    scale_meshes(armature, head_names, pivot, head_scale, body_scale, body_width_scale, arm_scale)
    scale_bones(armature, head_names, pivot, head_scale, body_scale, body_width_scale, arm_scale)
    bpy.context.view_layer.update()

    body_obj = bpy.data.objects.get("Body")
    if not body_obj:
        raise SystemExit("缺少 Body 网格")
    apply_a_pose(armature, body_obj, angle=-1.1)
    bpy.context.view_layer.update()

    replace_textures()
    images = {path.stem: bpy.data.images.get(f"gen_{path.stem}") for path in TEXTURE_DIR.glob("*.png")}
    ear_outer_mat = make_textured_material("EarOuter", images["ear_outer"], 0.7)
    ear_inner_mat = make_solid_material("EarInner", "#B39AD6", 0.72)
    hair_mat = bpy.data.materials.get("N00_000_Hair_00_HAIR")
    if not hair_mat:
        raise SystemExit("缺少头发材质 N00_000_Hair_00_HAIR")
    for material_name in ("N00_000_Hair_00_HAIR", "N00_000_00_HairBack_00_HAIR"):
        material = bpy.data.materials.get(material_name)
        if not material or not material.use_nodes:
            continue
        mtoon = material.node_tree.nodes.get("Mtoon1Material.Mtoon1Output")
        if mtoon and "Shade Color" in mtoon.inputs:
            mtoon.inputs["Shade Color"].default_value = (0.70, 0.74, 0.84, 1.0)
    headband_mat = make_solid_material("Headband", CONFIG["palette"]["headband"], 0.45, 0.05)
    headband_side_mat = make_solid_material("HeadbandSide", CONFIG["palette"]["headbandSide"], 0.45, 0.05)
    headband_accent_mat = make_solid_material("HeadbandAccent", CONFIG["palette"]["headbandAccent"], 0.25, 0.20)

    face_obj = bpy.data.objects.get("Face")
    hair_obj = bpy.data.objects.get("Hair001")
    if not face_obj or not hair_obj:
        raise SystemExit("缺少 Face 或 Hair001 网格")
    points = [obj.matrix_world @ Vector(corner) for obj in (face_obj, hair_obj) for corner in obj.bound_box]
    head_top = max(point.z for point in points)
    head_bottom = min(point.z for point in points)
    half_width = max(abs(point.x) for point in points)
    head_height = head_top - head_bottom
    print(f"HEAD_BOUNDS top={head_top:.4f} bottom={head_bottom:.4f} half_width={half_width:.4f} height={head_height:.4f}")

    for side, label in ((1, "R"), (-1, "L")):
        make_ear_prism(f"CatEar{label}", side, half_width, head_top, head_height, ear_outer_mat, armature, head_bone_name)
        make_ear_inner(f"CatEarInner{label}", side, half_width, head_top, head_height, ear_inner_mat, armature, head_bone_name)

    ahoge_points = [
        Vector((0.0, 0.0, head_top + 0.00 * head_height)),
        Vector((0.015 * half_width, 0.0, head_top + 0.14 * head_height)),
        Vector((0.04 * half_width, 0.0, head_top + 0.26 * head_height)),
        Vector((0.10 * half_width, 0.0, head_top + 0.34 * head_height)),
        Vector((0.16 * half_width, 0.0, head_top + 0.31 * head_height)),
        Vector((0.17 * half_width, 0.0, head_top + 0.25 * head_height)),
        Vector((0.13 * half_width, 0.0, head_top + 0.25 * head_height)),
    ]
    ahoge_radii = [0.05 * head_height * factor for factor in (0.30, 0.28, 0.24, 0.20, 0.14, 0.08, 0.03)]
    ahoge_mat = make_emissive_textured_material("Ahoge", images["ahoge"])
    texture_node = next((node for node in ahoge_mat.node_tree.nodes if node.type == "TEX_IMAGE"), None)
    if texture_node:
        uv_node = ahoge_mat.node_tree.nodes.new("ShaderNodeUVMap")
        uv_node.uv_map = "UVMap"
        ahoge_mat.node_tree.links.new(uv_node.outputs["UV"], texture_node.inputs["Vector"])
    ahoge = make_tube("Ahoge", ahoge_points, ahoge_radii, ahoge_mat, armature, head_bone_name)
    map_tube_uv(ahoge, len(ahoge_points), 8, 0.95, 0.05)
    make_headband(armature, head_bone_name, half_width, head_top, head_height, headband_mat, headband_side_mat, headband_accent_mat)

    bpy.context.view_layer.update()
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    min_z = min(
        (obj.matrix_world @ Vector(corner)).z
        for obj in meshes
        for corner in obj.bound_box
    )
    armature.location.z = -min_z
    bpy.context.view_layer.update()
    print(f"GROUNDED min_z={min_z:.4f} armature_z={armature.location.z:.4f}")

    ranges = ac.make_actions(armature, 30)
    armature.animation_data.action = None
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = max(ranges.values()) if ranges else 1
    scene.render.fps = 30

    face_shape_keys = face_obj.data.shape_keys.key_blocks if face_obj.data.shape_keys else []
    expected = ac.load_config()["validation"]["arkitCount"]
    print(f"FINAL_FACE_SHAPEKEYS {len(face_shape_keys)} expected_arkit={expected}")
    if len(face_shape_keys) < expected + 1:
        raise SystemExit("Face 形态键数量异常")

    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), check_existing=False)
    print(f"SAVED {OUT_BLEND}")


main()
