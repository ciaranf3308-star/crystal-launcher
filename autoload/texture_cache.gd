extends Node
## TextureCache — background image decode, LRU texture cache, thumbnails.
##
## Plain Launcher's anti-pattern (synchronous Image.load_from_file on every
## selection change) is exactly what this exists to avoid. All decoding
## happens on a worker thread; the main thread only creates ImageTextures
## from already-decoded Images and dispatches callbacks.

const MAX_ENTRIES := 96

var _cache: Dictionary = {}   # key -> {texture: Texture2D, order: int}
var _order := 0
var _callbacks: Dictionary = {}  # key -> Array[Callable]

var _mutex := Mutex.new()
var _queue: Array = []    # [key, path, max_size]
var _pending: Array = []  # [key, Image or null]
var _queued_keys := {}
var _thread: Thread
var _quit := false


func _ready() -> void:
	_thread = Thread.new()
	_thread.start(_worker)


func _exit_tree() -> void:
	_quit = true
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _process(_delta: float) -> void:
	_drain_pending()


## Request a texture. Callback receives (key: String, texture: Texture2D or null).
## If cached, the callback fires deferred immediately. Otherwise the image is
## decoded on the worker thread (optionally downscaled to max_size px) and the
## callback fires when ready.
func request(key: String, path: String, max_size: int, callback: Callable) -> void:
	_mutex.lock()
	if _cache.has(key):
		var tex: Texture2D = _cache[key]["texture"]
		_cache[key]["order"] = _order
		_order += 1
		_mutex.unlock()
		callback.call_deferred(key, tex)
		return
	if not _callbacks.has(key):
		_callbacks[key] = []
	_callbacks[key].append(callback)
	if not _queued_keys.has(key):
		_queued_keys[key] = true
		_queue.append([key, path, max_size])
	_mutex.unlock()


func cached(key: String) -> Texture2D:
	_mutex.lock()
	var tex: Texture2D = null
	if _cache.has(key):
		tex = _cache[key]["texture"]
		_cache[key]["order"] = _order
		_order += 1
	_mutex.unlock()
	return tex


func clear() -> void:
	_mutex.lock()
	_cache.clear()
	_mutex.unlock()


func _drain_pending() -> void:
	var batch: Array = []
	_mutex.lock()
	batch = _pending.duplicate()
	_pending.clear()
	_mutex.unlock()
	for item: Array in batch:
		var key: String = item[0]
		var img: Image = item[1]
		var tex: Texture2D = null
		if img != null:
			tex = ImageTexture.create_from_image(img)
		_mutex.lock()
		if tex != null:
			_cache[key] = {"texture": tex, "order": _order}
			_order += 1
			_evict_locked()
		_queued_keys.erase(key)
		var cbs: Array = _callbacks.get(key, [])
		_callbacks.erase(key)
		_mutex.unlock()
		for cb: Callable in cbs:
			if cb.is_valid():
				cb.call(key, tex)


func _evict_locked() -> void:
	while _cache.size() > MAX_ENTRIES:
		var oldest_key: String = ""
		var oldest_order := 1 << 60
		for k: String in _cache:
			if _cache[k]["order"] < oldest_order:
				oldest_order = _cache[k]["order"]
				oldest_key = k
		if oldest_key == "":
			break
		_cache.erase(oldest_key)


func _worker() -> void:
	while not _quit:
		var job: Array = []
		_mutex.lock()
		if not _queue.is_empty():
			job = _queue.pop_front()
		_mutex.unlock()
		if job.is_empty():
			OS.delay_msec(10)
			continue
		var key: String = job[0]
		var path: String = job[1]
		var max_size: int = job[2]
		var img: Image = null
		if path.begins_with("saf://"):
			# Android SAF grant: bytes come from the plugin's
			# ContentResolver read; Godot's FileAccess can't see them.
			var bytes: PackedByteArray = CrystalPlugin.saf_read_bytes(path.trim_prefix("saf://"))
			img = _image_from_bytes(bytes)
		elif FileAccess.file_exists(path):
			img = Image.load_from_file(path)
		if img != null and max_size > 0:
			if img.get_width() > max_size or img.get_height() > max_size:
				var scale := minf(float(max_size) / img.get_width(),
					float(max_size) / img.get_height())
				img.resize(int(img.get_width() * scale),
					int(img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
		_mutex.lock()
		_pending.append([key, img])
		_mutex.unlock()


## Decode an image from raw bytes (SAF reads). Sniffs the container magic —
## Godot 4 has no generic load-from-buffer, so each format is tried by its
## signature. Returns null when the bytes aren't a decodable image.
static func _image_from_bytes(bytes: PackedByteArray) -> Image:
	if bytes.size() < 16:
		return null
	var img := Image.new()
	var err := ERR_INVALID_DATA
	if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[2] == 0x46 and bytes[3] == 0x46:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return null
	return img
