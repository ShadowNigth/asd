extends Node
## ModelLoader: Loads Godot-ready .glb models directly OR from compressed .glb.gz
## files in res://assets/models/ using Godot 4's built-in GLTFDocument.

var _decompressed_cache: Dictionary = {} # glb_path -> PackedByteArray

func model_exists(glb_path: String) -> bool:
	return ResourceLoader.exists(glb_path) or FileAccess.file_exists(glb_path + ".gz")

func _load_glb_bytes(gz_path: String) -> PackedByteArray:
	if _decompressed_cache.has(gz_path):
		return _decompressed_cache[gz_path]
	var raw := FileAccess.get_file_as_bytes(gz_path)
	if raw.is_empty():
		return PackedByteArray()
	var glb_bytes := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if glb_bytes.is_empty():
		push_error("Failed to decompress GLB.GZ: %s" % gz_path)
		return PackedByteArray()
	# Cache small/medium models (<= 16 MB) so weapon switches are instant
	if glb_bytes.size() <= 16 * 1024 * 1024:
		_decompressed_cache[gz_path] = glb_bytes
	return glb_bytes

func instantiate_model(glb_path: String) -> Node3D:
	if ResourceLoader.exists(glb_path):
		var scene: PackedScene = load(glb_path)
		if scene != null:
			var inst := scene.instantiate()
			if inst is Node3D:
				return inst as Node3D
			if inst != null:
				inst.queue_free()

	var gz_path := glb_path + ".gz"
	if not FileAccess.file_exists(gz_path):
		return null

	var glb_bytes := _load_glb_bytes(gz_path)
	if glb_bytes.is_empty():
		return null

	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_buffer(glb_bytes, "", state)
	if err != OK:
		push_error("GLTFDocument.append_from_buffer failed (%d) for %s" % [err, gz_path])
		return null

	var node := gltf.generate_scene(state)
	if node is Node3D:
		return node as Node3D
	if node != null:
		node.queue_free()
	return null
