extends Node

# Local outfit-captioning client for Ollama vision models.
# Sends a cropped in-game character image plus equipped-item metadata and returns
# structured Stable Diffusion clothing tags.

signal analysis_complete(result, from_cache)
signal analysis_error(message)
signal status_changed(message)

const CACHE_PATH = "user://portrait_generator_outfit_cache.json"

var busy = false
var _http = null
var _cache = {}
var _pending_cache_key = ""

func update():
    pass

func _ready():
    _load_cache()
    _http = HTTPRequest.new()
    _http.connect("request_completed", self, "_on_request_completed")
    add_child(_http)

func analyze_outfit(image, equipment_context, cache_key, server_url, model_name, force_refresh = false):
    if busy:
        emit_signal("analysis_error", "An outfit analysis is already running")
        return
    if image == null or image.get_width() <= 0 or image.get_height() <= 0:
        emit_signal("analysis_error", "The captured character image is empty")
        return

    if not force_refresh and _cache.has(cache_key):
        call_deferred("_emit_cached_result", _cache[cache_key])
        return

    server_url = str(server_url).strip_edges().rstrip("/")
    model_name = str(model_name).strip_edges()
    if server_url == "":
        emit_signal("analysis_error", "Enter an Ollama server URL")
        return
    if model_name == "":
        emit_signal("analysis_error", "Enter an Ollama vision model name")
        return

    var prepared = image.duplicate()
    if prepared.is_compressed():
        var decompress_error = prepared.decompress()
        if decompress_error != OK:
            emit_signal("analysis_error", "Could not decompress the captured image")
            return
    if prepared.get_format() != Image.FORMAT_RGB8 and prepared.get_format() != Image.FORMAT_RGBA8:
        prepared.convert(Image.FORMAT_RGBA8)

    var png_data = prepared.save_png_to_buffer()
    if png_data.size() == 0:
        emit_signal("analysis_error", "Could not encode the captured image as PNG")
        return

    var schema = _response_schema()
    var prompt = _build_analysis_prompt(equipment_context, schema)
    var payload = JSON.print({
        "model": model_name,
        "stream": false,
        "think": false,
        "keep_alive": 0,
        "format": schema,
        "options": {"temperature": 0},
        "messages": [{
            "role": "user",
            "content": prompt,
            "images": [Marshalls.raw_to_base64(png_data)]
        }]
    })

    _pending_cache_key = cache_key
    busy = true
    emit_signal("status_changed", "Sending character image to Ollama...")
    var headers = ["Content-Type: application/json"]
    var err = _http.request(server_url + "/api/chat", headers, false, HTTPClient.METHOD_POST, payload)
    if err != OK:
        busy = false
        _pending_cache_key = ""
        emit_signal("analysis_error", "Could not contact Ollama (error %d)" % err)

func _emit_cached_result(result):
    emit_signal("status_changed", "Loaded cached outfit analysis")
    emit_signal("analysis_complete", result, true)

func _on_request_completed(result, response_code, _headers, body):
    busy = false

    if result != HTTPRequest.RESULT_SUCCESS:
        _pending_cache_key = ""
        emit_signal("analysis_error", "Ollama request failed. Make sure Ollama is running")
        return

    if response_code != 200:
        var details = body.get_string_from_utf8()
        _pending_cache_key = ""
        emit_signal("analysis_error", "Ollama returned HTTP %d: %s" % [response_code, _shorten(details, 260)])
        return

    var envelope = JSON.parse(body.get_string_from_utf8())
    if envelope.error != OK or not (envelope.result is Dictionary):
        _pending_cache_key = ""
        emit_signal("analysis_error", "Ollama returned invalid JSON")
        return

    var message = envelope.result.get("message", {})
    var content = str(message.get("content", "")).strip_edges()
    var parsed_result = _parse_structured_content(content)
    if parsed_result == null:
        _pending_cache_key = ""
        emit_signal("analysis_error", "The vision model did not return a valid outfit description")
        return

    if _pending_cache_key != "":
        _cache[_pending_cache_key] = parsed_result
        _save_cache()
    _pending_cache_key = ""

    emit_signal("status_changed", "Outfit analysis complete")
    emit_signal("analysis_complete", parsed_result, false)

func _parse_structured_content(content):
    if content.begins_with("```"):
        var first_newline = content.find("\n")
        if first_newline >= 0:
            content = content.substr(first_newline + 1)
        if content.ends_with("```"):
            content = content.substr(0, content.length() - 3)
        content = content.strip_edges()

    var parsed = JSON.parse(content)
    if parsed.error != OK or not (parsed.result is Dictionary):
        return null

    var positive_tags = _clean_tag_list(parsed.result.get("positive_tags", []))
    var negative_tags = _clean_tag_list(parsed.result.get("negative_tags", []))
    if positive_tags.empty():
        return null

    return {
        "positive_tags": positive_tags,
        "negative_tags": negative_tags,
        "confidence": clamp(float(parsed.result.get("confidence", 0.5)), 0.0, 1.0),
        "summary": str(parsed.result.get("summary", "")).strip_edges()
    }

func _clean_tag_list(value):
    var source = []
    if value is Array:
        source = value
    elif value is String:
        source = value.split(",")

    var cleaned = []
    var seen = {}
    for entry in source:
        var tag = str(entry).strip_edges().trim_prefix("-").strip_edges()
        while tag.ends_with(",") or tag.ends_with("."):
            tag = tag.substr(0, tag.length() - 1).strip_edges()
        var key = tag.to_lower()
        if tag == "" or seen.has(key):
            continue
        seen[key] = true
        cleaned.append(tag)
        if cleaned.size() >= 30:
            break
    return cleaned

func _response_schema():
    return {
        "type": "object",
        "properties": {
            "positive_tags": {"type": "array", "items": {"type": "string"}},
            "negative_tags": {"type": "array", "items": {"type": "string"}},
            "confidence": {"type": "number"},
            "summary": {"type": "string"}
        },
        "required": ["positive_tags", "negative_tags", "confidence", "summary"]
    }

func _build_analysis_prompt(equipment_context, schema):
    return """Analyze this cropped 2D fantasy-game character image so its visible outfit can be recreated by an image-generation model.

Known equipped items:
%s

Rules:
1. Describe only visible clothing, armor, accessories, footwear, and held equipment.
2. Use the equipped-item list as identification hints, but use the image to determine silhouette, coverage, colors, trim, layers, and visible accessories.
3. Crafting materials do not change clothing colors in this game. Do not turn armor crafting parts into literal wooden, stone, or metal garment trim. Materials may still describe a clearly visible weapon or tool.
4. Do not describe the character's face, hair, build, skin, pose, expression, background, user interface, or image style.
5. Use concise comma-ready Stable Diffusion tags, not sentences.
6. Include useful coverage tags such as high neckline, deep neckline, exposed midriff, bare shoulders, long sleeves, short skirt, or bare thighs.
7. Include negative tags for likely visual misreadings, such as long robe when the visible garment is cropped.
8. Do not invent items for empty equipment slots. If a detail is uncertain, omit it rather than guessing.
9. Return only JSON matching this schema:
%s
""" % [equipment_context, JSON.print(schema)]

func _load_cache():
    var file = File.new()
    if not file.file_exists(CACHE_PATH):
        _cache = {}
        return
    if file.open(CACHE_PATH, File.READ) != OK:
        _cache = {}
        return
    var parsed = JSON.parse(file.get_as_text())
    file.close()
    _cache = parsed.result if parsed.error == OK and parsed.result is Dictionary else {}

func _save_cache():
    var file = File.new()
    if file.open(CACHE_PATH, File.WRITE) == OK:
        file.store_string(JSON.print(_cache, "  "))
        file.close()

func clear_cache():
    _cache = {}
    _save_cache()

func _shorten(text, max_length):
    text = str(text).replace("\n", " ").replace("\r", " ")
    if text.length() <= max_length:
        return text
    return text.substr(0, max_length - 3) + "..."
