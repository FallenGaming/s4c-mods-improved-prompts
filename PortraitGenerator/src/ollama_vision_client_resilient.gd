extends "ollama_vision_client_strict.gd"

# Recovers useful tags from partially malformed model output and retries once when
# Ollama returns an unusable response. This avoids feeding JSON.parse() the model's
# free-form content, which otherwise prints noisy parse errors for truncated JSON.

const INVALID_RESPONSE_PATH = "user://portrait_generator_last_vision_response.txt"

var _request_server_url = ""
var _request_payload = {}
var _retry_attempt = 0

func _response_schema():
    return {
        "type": "object",
        "additionalProperties": false,
        "properties": {
            "positive_tags": {
                "type": "array",
                "minItems": 1,
                "maxItems": 24,
                "items": {"type": "string", "maxLength": 80}
            },
            "negative_tags": {
                "type": "array",
                "maxItems": 16,
                "items": {"type": "string", "maxLength": 80}
            },
            "confidence": {
                "type": "number",
                "minimum": 0.0,
                "maximum": 1.0
            }
        },
        "required": ["positive_tags", "negative_tags", "confidence"]
    }

func _build_analysis_prompt(equipment_context, _schema):
    return """Inspect the attached game character and return only a compact JSON object.

Known equipped items:
%s

Describe only visible clothing, armor, accessories, footwear, and held equipment. Use the equipment list only as a hint. Determine colors, shape, coverage, layers, and trim from the image.

Never output character appearance, camera/framing tags, item IDs, slot names, crafting fields, or key=value metadata. Crafting materials do not recolor clothing. A visible weapon material such as wooden club is allowed.

Use this exact structure and no markdown:
{"positive_tags":["short visual tag"],"negative_tags":["likely clothing misread"],"confidence":0.9}

Keep positive_tags at 24 items or fewer and negative_tags at 16 items or fewer.""" % equipment_context

func _build_retry_prompt():
    return """Return one compact JSON object only. Do not explain your answer and do not use markdown.

Describe only visible clothes, armor, accessories, footwear, and held equipment in the attached character image. Do not include the character's body, hair, face, pose, framing, background, raw item names, IDs, or crafting metadata.

Required shape:
{"positive_tags":["visual outfit tag"],"negative_tags":["likely outfit misread"],"confidence":0.9}

Use at most 20 short positive tags and 12 short negative tags."""

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
    _request_server_url = server_url
    _request_payload = {
        "model": model_name,
        "stream": false,
        "think": false,
        "keep_alive": 0,
        "format": schema,
        "options": {
            "temperature": 0,
            "num_predict": 320
        },
        "messages": [{
            "role": "user",
            "content": _build_analysis_prompt(equipment_context, schema),
            "images": [Marshalls.raw_to_base64(png_data)]
        }]
    }
    _retry_attempt = 0
    _pending_cache_key = cache_key
    busy = true
    _send_current_request("Sending character image to Ollama...")

func _send_current_request(status_message):
    emit_signal("status_changed", status_message)
    var headers = ["Content-Type: application/json"]
    var err = _http.request(
        _request_server_url + "/api/chat",
        headers,
        false,
        HTTPClient.METHOD_POST,
        JSON.print(_request_payload)
    )
    if err != OK:
        _finish_error("Could not contact Ollama (error %d)" % err)

func _on_request_completed(result, response_code, _headers, body):
    if result != HTTPRequest.RESULT_SUCCESS:
        _finish_error("Ollama request failed. Make sure Ollama is running")
        return

    if response_code != 200:
        var details = body.get_string_from_utf8()
        _finish_error("Ollama returned HTTP %d: %s" % [response_code, _shorten(details, 260)])
        return

    # The outer Ollama response is produced by the server and should always be valid JSON.
    var envelope = JSON.parse(body.get_string_from_utf8())
    if envelope.error != OK or not (envelope.result is Dictionary):
        _finish_error("Ollama returned an invalid API response")
        return
    if envelope.result.has("error"):
        _finish_error("Ollama error: %s" % str(envelope.result.get("error", "Unknown error")))
        return

    var message = envelope.result.get("message", {})
    var content = str(message.get("content", "")).strip_edges()
    var parsed_result = _parse_structured_content(content)

    if parsed_result == null:
        _save_invalid_response(content)
        if _retry_attempt < 1:
            _retry_attempt += 1
            _request_payload["messages"][0]["content"] = _build_retry_prompt()
            _request_payload["options"]["num_predict"] = 256
            call_deferred("_send_current_request", "The first response was malformed; retrying once...")
            return
        _finish_error("The vision model returned malformed JSON twice. The last response was saved for troubleshooting")
        return

    if _pending_cache_key != "":
        _cache[_pending_cache_key] = parsed_result
        _save_cache()

    _pending_cache_key = ""
    _request_payload = {}
    _request_server_url = ""
    _retry_attempt = 0
    busy = false
    emit_signal("status_changed", "Outfit analysis complete")
    emit_signal("analysis_complete", parsed_result, false)

func _parse_structured_content(content):
    content = _strip_response_wrappers(content)

    var positive_tags = _clean_tag_list(_extract_string_list(content, "positive_tags"))
    var negative_tags = _clean_tag_list(_extract_string_list(content, "negative_tags"))
    if positive_tags.empty():
        return null

    return {
        "positive_tags": positive_tags,
        "negative_tags": negative_tags,
        "confidence": clamp(_extract_number(content, "confidence", 0.5), 0.0, 1.0),
        "summary": ""
    }

func _strip_response_wrappers(content):
    var cleaned = str(content).strip_edges()
    if cleaned.begins_with("```"):
        var first_newline = cleaned.find("\n")
        if first_newline >= 0:
            cleaned = cleaned.substr(first_newline + 1)
        if cleaned.ends_with("```"):
            cleaned = cleaned.substr(0, cleaned.length() - 3)
    return cleaned.strip_edges()

func _find_value_start(content, key):
    var key_pos = content.find('"' + key + '"')
    if key_pos < 0:
        key_pos = content.find(key)
    if key_pos < 0:
        return -1

    var colon_pos = content.find(":", key_pos + key.length())
    if colon_pos < 0:
        return -1

    var value_pos = colon_pos + 1
    while value_pos < content.length():
        var character = content.substr(value_pos, 1)
        if character != " " and character != "\t" and character != "\n" and character != "\r":
            break
        value_pos += 1
    return value_pos

func _extract_string_list(content, key):
    var value_pos = _find_value_start(content, key)
    if value_pos < 0 or value_pos >= content.length():
        return []

    var first_character = content.substr(value_pos, 1)
    if first_character == "[":
        return _scan_quoted_strings(content, value_pos + 1)
    if first_character == '"':
        var one_value = _read_quoted_string(content, value_pos)
        if one_value == null:
            return []
        return str(one_value).split(",")
    return []

func _scan_quoted_strings(content, start_pos):
    var values = []
    var in_string = false
    var escaped = false
    var current = ""

    for index in range(start_pos, content.length()):
        var character = content.substr(index, 1)
        if in_string:
            if escaped:
                current += _decode_escape(character)
                escaped = false
            elif character == "\\":
                escaped = true
            elif character == '"':
                in_string = false
                if current.strip_edges() != "":
                    values.append(current)
                current = ""
            else:
                current += character
        else:
            if character == '"':
                in_string = true
            elif character == "]":
                break

    # Intentionally discard a final unterminated string while preserving all complete tags.
    return values

func _read_quoted_string(content, quote_pos):
    var escaped = false
    var current = ""
    for index in range(quote_pos + 1, content.length()):
        var character = content.substr(index, 1)
        if escaped:
            current += _decode_escape(character)
            escaped = false
        elif character == "\\":
            escaped = true
        elif character == '"':
            return current
        else:
            current += character
    return null

func _decode_escape(character):
    match character:
        "n", "r", "t":
            return " "
        '"':
            return '"'
        "\\":
            return "\\"
        "/":
            return "/"
        _:
            return character

func _extract_number(content, key, default_value):
    var value_pos = _find_value_start(content, key)
    if value_pos < 0:
        return default_value

    var number_text = ""
    var valid_characters = "0123456789.+-eE"
    for index in range(value_pos, content.length()):
        var character = content.substr(index, 1)
        if valid_characters.find(character) < 0:
            break
        number_text += character

    if number_text.is_valid_float():
        return float(number_text)
    return default_value

func _save_invalid_response(content):
    var file = File.new()
    if file.open(INVALID_RESPONSE_PATH, File.WRITE) == OK:
        file.store_string(str(content))
        file.close()

func _finish_error(message):
    busy = false
    _pending_cache_key = ""
    _request_payload = {}
    _request_server_url = ""
    _retry_attempt = 0
    emit_signal("analysis_error", message)
