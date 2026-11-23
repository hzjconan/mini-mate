"""Inspect Body material slots, boundary loops and armature bones (dev helper)."""

from __future__ import annotations

from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
BLEND = ROOT / "work" / "phase1" / "minimate_phase1.blend"


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(BLEND))
    scene = bpy.context.scene
    armature = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    body = bpy.data.objects["Body"]
    mesh = body.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()

    tops_faces = [f for f in bm.faces if f.material_index == 3]
    # Connected components of the Tops faces.
    remaining = set(tops_faces)
    component = 0
    while remaining:
        seed = remaining.pop()
        stack = [seed]
        faces = [seed]
        while stack:
            face = stack.pop()
            for edge in face.edges:
                for neighbor in edge.link_faces:
                    if neighbor in remaining and neighbor.material_index == 3:
                        remaining.discard(neighbor)
                        stack.append(neighbor)
                        faces.append(neighbor)
        verts = {v for f in faces for v in f.verts}
        world = [body.matrix_world @ v.co for v in verts]
        print(
            f"COMPONENT {component} faces={len(faces)} verts={len(verts)} "
            f"x=[{min(p.x for p in world):.3f},{max(p.x for p in world):.3f}] "
            f"y=[{min(p.y for p in world):.3f},{max(p.y for p in world):.3f}] "
            f"z=[{min(p.z for p in world):.3f},{max(p.z for p in world):.3f}]"
        )
        component += 1

    edges = [e for e in bm.edges if len(e.link_faces) == 1 and e.link_faces[0].material_index == 3]
    adjacency: dict[int, set[int]] = {}
    for edge in edges:
        a, b = edge.verts[0].index, edge.verts[1].index
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)
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
        world = [body.matrix_world @ bm.verts[v].co for v in loop]
        print(f"LOOP n={len(loop)}")
        for i in range(0, len(loop), max(1, len(loop) // 10)):
            p = world[i]
            print(f"   {i:3d} ({p.x:+.3f},{p.y:+.3f},{p.z:.3f})")
    bm.free()

    print("BONES")
    for bone in armature.data.bones:
        if any(key in bone.name for key in ("UpperArm", "LowerArm", "Hand", "Shoulder", "Hips", "Spine", "Chest", "Neck")):
            head = armature.matrix_world @ bone.head_local
            tail = armature.matrix_world @ bone.tail_local
            print(
                f"  {bone.name}: head=({head.x:.4f},{head.y:.4f},{head.z:.4f}) "
                f"tail=({tail.x:.4f},{tail.y:.4f},{tail.z:.4f})"
            )


main()
