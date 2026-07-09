extends RefCounted
class_name LutLoader
## Module E: parses Adobe/DaVinci-standard .cube 3D LUT files into a
## Texture3D that binds directly to video_compositor.gdshader's
## lut_texture uniform.
##
## Real parsing — on malformed or unsupported input this returns null
## and push_error()s the reason. It never fabricates an identity/fallback
## LUT in place of a bad file; callers must treat null as "grading
## unavailable for this LUT" and surface that to the user, per the
## "validate all media inputs, never invent data" standard.
##
## Only LUT_3D_SIZE (3D) cubes are supported. LUT_1D_SIZE (1D) cubes are
## explicitly rejected with a clear error rather than silently
## misinterpreted as 3D data.

const MIN_SIZE := 2
const MAX_SIZE := 128 # sane upper bound — guards against OOM from a corrupt/hostile file

class LutResult:
	var texture: Texture3D
	var size: int = 0
	var domain_min: Vector3 = Vector3.ZERO
	var domain_max: Vector3 = Vector3.ONE
	var title: String = ""

## Returns a populated LutResult, or null on any parse/validation failure.
static func load_cube_file(path: String) -> LutResult:
	if path.get_extension().to_lower() != "cube":
		push_error("LutLoader: '%s' is not a .cube file" % path)
		return null
	if not FileAccess.file_exists(path):
		push_error("LutLoader: file not found: '%s'" % path)
		return null

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("LutLoader: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return null

	var result := LutResult.new()
	var size := -1
	var values := PackedFloat32Array()

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "" or line.begins_with("#"):
			continue

		if line.begins_with("TITLE"):
			result.title = line.substr(5).strip_edges().trim_prefix("\"").trim_suffix("\"")
			continue

		if line.begins_with("LUT_1D_SIZE"):
			push_error("LutLoader: '%s' is a 1D LUT — only LUT_3D_SIZE cubes are supported" % path)
			return null

		if line.begins_with("LUT_3D_SIZE"):
			var parts := line.split(" ", false)
			if parts.size() < 2 or not parts[1].is_valid_int():
				push_error("LutLoader: malformed LUT_3D_SIZE line in '%s'" % path)
				return null
			size = int(parts[1])
			if size < MIN_SIZE or size > MAX_SIZE:
				push_error("LutLoader: LUT_3D_SIZE %d in '%s' is outside the supported range [%d, %d]" % [size, path, MIN_SIZE, MAX_SIZE])
				return null
			continue

		if line.begins_with("DOMAIN_MIN"):
			var v: Variant = _parse_vec3(line.substr(10))
			if v == null:
				push_error("LutLoader: malformed DOMAIN_MIN line in '%s'" % path)
				return null
			result.domain_min = v
			continue

		if line.begins_with("DOMAIN_MAX"):
			var v: Variant = _parse_vec3(line.substr(10))
			if v == null:
				push_error("LutLoader: malformed DOMAIN_MAX line in '%s'" % path)
				return null
			result.domain_max = v
			continue

		# Anything else at this point should be a "r g b" data row.
		var row: Variant = _parse_vec3(line)
		if row == null:
			push_error("LutLoader: unrecognized/malformed line in '%s': '%s'" % [path, line])
			return null
		values.append(row.x)
		values.append(row.y)
		values.append(row.z)

	if size == -1:
		push_error("LutLoader: '%s' has no LUT_3D_SIZE directive" % path)
		return null

	var expected_count := size * size * size * 3
	if values.size() != expected_count:
		push_error("LutLoader: '%s' has %d data values, expected %d for LUT_3D_SIZE %d" % [path, values.size(), expected_count, size])
		return null

	var texture := _build_texture(values, size)
	if texture == null:
		return null

	result.size = size
	result.texture = texture
	return result

## .cube data rows are ordered red-fastest, green-next, blue-slowest:
## flat_index = b*size*size + g*size + r. Godot's ImageTexture3D wants one
## Image per Z-slice (blue), each size x size (r maps to x, g maps to y).
## Stored as RGBAF (float) to avoid 8-bit banding on subtle grades.
static func _build_texture(values: PackedFloat32Array, size: int) -> Texture3D:
	var slices: Array[Image] = []
	for b in range(size):
		var img := Image.create(size, size, false, Image.FORMAT_RGBAF)
		for g in range(size):
			for r in range(size):
				var idx := (b * size * size + g * size + r) * 3
				img.set_pixel(r, g, Color(values[idx], values[idx + 1], values[idx + 2], 1.0))
		slices.append(img)

	var tex := ImageTexture3D.new()
	var err := tex.create(Image.FORMAT_RGBAF, size, size, size, false, slices)
	if err != OK:
		push_error("LutLoader: ImageTexture3D.create() failed (error %d) for a %dx%dx%d LUT" % [err, size, size, size])
		return null
	return tex

static func _parse_vec3(text: String) -> Variant:
	var parts := text.strip_edges().split(" ", false)
	if parts.size() != 3:
		return null
	for p in parts:
		if not p.is_valid_float():
			return null
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
