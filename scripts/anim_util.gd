class_name AnimUtil
extends RefCounted

## Builds SpriteFrames at runtime from loose PNG sequences under Png/.
## Built resources are cached per directory-set so many actors of the same
## kind share one SpriteFrames instead of re-listing and re-loading files.

static var _cache: Dictionary = {}

static func list_pngs(dir_path: String) -> Array:
	var files := []
	var dir := DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if not dir.current_is_dir():
				# Exported builds ship "*.png.import"/"*.png.remap" entries
				# instead of the loose source .png, so strip those suffixes;
				# load() still resolves the bare .png path via the remap.
				var name := f.trim_suffix(".import").trim_suffix(".remap")
				if name.ends_with(".png"):
					var path: String = dir_path.path_join(name)
					if not files.has(path):
						files.append(path)
			f = dir.get_next()
		dir.list_dir_end()
	files.sort()
	return files

static func build_frames(sf: SpriteFrames, anim_name: String, dir_path: String, fps: float, loop: bool) -> void:
	if not sf.has_animation(anim_name):
		sf.add_animation(anim_name)
	sf.set_animation_speed(anim_name, fps)
	sf.set_animation_loop(anim_name, loop)
	for path in list_pngs(dir_path):
		var tex := load(path)
		if tex:
			sf.add_frame(anim_name, tex)

## defs: Array of [anim_name, dir_path, fps, loop]. Returns a shared,
## cached SpriteFrames built from those PNG directories.
static func cached_frames(defs: Array) -> SpriteFrames:
	var key := str(defs)
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for d in defs:
		build_frames(sf, d[0], d[1], d[2], d[3])
	_cache[key] = sf
	return sf
