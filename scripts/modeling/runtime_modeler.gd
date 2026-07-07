extends Node
class_name RuntimeModeler
## Module D: SurfaceTool-based primitive generator. Lets users generate
## simple 3D geometry at runtime (extruded text/path, primitives) without
## an "export to Blender" round trip. Real-shadow-casting default material
## on everything this produces, so modeled geometry sits naturally
## alongside video quads under the same lighting rig.

static func default_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Real-shadow-casting default per Module D — this is a real lit
	# material, not the unshaded video_compositor path.
	return mat

## --- Primitives ---

static func make_cube(size: Vector3 = Vector3.ONE) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var corners := [
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
	]
	var faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7],
		[1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	for face in faces:
		var a = corners[face[0]]; var b = corners[face[1]]
		var c = corners[face[2]]; var d = corners[face[3]]
		st.add_triangle_fan(PackedVector3Array([a, b, c]))
		st.add_triangle_fan(PackedVector3Array([a, c, d]))
	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func make_extruded_polygon(points: PackedVector2Array, depth: float = 0.2) -> ArrayMesh:
	## Simple straight extrusion along Z: front face, back face, side walls.
	## Points should be a simple (non-self-intersecting) polygon outline.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if points.size() < 3:
		return st.commit()

	var front: Array = []
	var back: Array = []
	for p in points:
		front.append(Vector3(p.x, p.y, depth / 2.0))
		back.append(Vector3(p.x, p.y, -depth / 2.0))

	# Fan-triangulate front/back (assumes convex-ish outline; swap for an
	# ear-clipping triangulator if users draw concave paths).
	for i in range(1, points.size() - 1):
		st.add_triangle_fan(PackedVector3Array([front[0], front[i], front[i + 1]]))
		st.add_triangle_fan(PackedVector3Array([back[0], back[i + 1], back[i]]))

	# Side walls connecting front/back rings.
	for i in range(points.size()):
		var j := (i + 1) % points.size()
		st.add_triangle_fan(PackedVector3Array([front[i], front[j], back[j]]))
		st.add_triangle_fan(PackedVector3Array([front[i], back[j], back[i]]))

	st.generate_normals()
	return st.commit()

static func make_text_mesh(text: String, font: Font, font_size: int = 48, depth: float = 0.15) -> ArrayMesh:
	## Extrudes each glyph's outline into 3D geometry, replacing the
	## Label3D stand-in from Phase 1's text_layer.gd.
	## TODO: Godot 4 doesn't expose glyph outline polygons through a
	## stable public API in all versions — if `font.get_glyph_contours`
	## (or equivalent TextServer call) isn't available on your Godot
	## build, fall back to rendering the text to a Viewport texture and
	## extruding a flat card instead of true per-glyph geometry. Documented
	## here as an open risk, not silently papered over.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	push_warning("RuntimeModeler.make_text_mesh: glyph extrusion not yet implemented — see TODO in source")
	return st.commit()

static func make_path_ribbon(path_points: PackedVector3Array, width: float = 0.1) -> ArrayMesh:
	## For "text-on-path" / simple ribbon geometry along an arbitrary
	## 3D path (Module G kinetic text-on-path reuses this).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	if path_points.size() < 2:
		return st.commit()
	for i in range(path_points.size()):
		var dir: Vector3
		if i == 0:
			dir = (path_points[1] - path_points[0]).normalized()
		elif i == path_points.size() - 1:
			dir = (path_points[i] - path_points[i - 1]).normalized()
		else:
			dir = (path_points[i + 1] - path_points[i - 1]).normalized()
		var side := dir.cross(Vector3.UP).normalized() * (width / 2.0)
		st.add_vertex(path_points[i] - side)
		st.add_vertex(path_points[i] + side)
	st.generate_normals()
	return st.commit()
