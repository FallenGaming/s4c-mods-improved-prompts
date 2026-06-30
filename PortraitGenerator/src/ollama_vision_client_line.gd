extends "ollama_vision_client_resilient_v2.gd"

# Qwen vision models do not always honor JSON/schema output reliably. This client
# requests a simple three-line protocol and accepts JSON, labeled lines, bullets,
# pipe-separated tags, comma-separated tags, or a final plain-text fallback.

const LINE_RESPONSE_PATH = "user://portrait_generator_last_vision_response.txt"

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

    _request_server_url = server_url
    _request_payload = {
        "model": model_name,
        "stream": false,
        "think": false,
        "keep_alive": 0,
        "options": {
            "temperature": 0,
            "num_predict": 280
        },
        "messages": [{
            "role": "user",
            "content": _build_line_prompt(equipment_context),
            "images": [Marshalls.raw_to_base64(png_data)]
        }]
    }

    _retry_attempt = 0
    _pending_cache_key = cache_key
    busy = true
    _send_current_request("Sending character image to Ollama...")

func _build_line_prompt(equipment_context):
    return """Inspect the attached fantasy-game character image.

Equipment hints:
%s

Describe ONLY visible clothing, armor, accessories, footwear, and held equipment. Use the equipment list only as a hint. Determine garment shape, colors, coverage, layers, and trim from the image.

Never describe hair, eyes, skin, face, body shape, height, breasts, hips, pose, camera framing, background, art style, raw item IDs, slot names, or crafting fields. Crafting materials do not recolor clothing. A visible held item such as a wooden club is allowed.

Reply with exactly these three labeled lines. Do not use JSON or markdown:
OUTFIT: short tag | short tag | short tag
NEGATIVE: likely clothing misread | likely clothing misread
CONFIDENCE: 0.90

Use no more than 24 OUTFIT tags and 12 NEGATIVE tags.""" % equipment_context

func _build_line_retry_prompt():
    return """Look at the attached character image and reply with ONE line only.

Describe only visible clothes, armor, accessories, footwear, and held equipment. Do not describe the person, pose, camera, background, raw item names, IDs, or crafting data.

Required format:
OUTFIT: tag | tag | tag

Do not use JSON, markdown, bullets, or explanations."""

func _on_request_completed(result, response_code, _headers, body):
    if result != HTTPRequest.RESULT_SUCCESS:
        _finish_error("Ollama request failed. Make sure Ollama is running")
        return

    if response_code != 200:
        var details = body.get_string_from_utf8()
        _finish_error("Ollama returned HTTP %d: %s" % [response_code, _shorten(details, 260)])
        return

    var envelope = JSON.parse(body.get_string_from_utf8())
    if envelope.error != OK or not (envelope.result is Dictionary):
        _finish_error("Ollama returned an invalid API response")
        return
    if envelope.result.has("error"):
        _finish_error("Ollama error: %s" % str(envelope.result.get("error", "Unknown error")))
        return

    var message = envelope.result.get("message", {})
    var content = str(message.get("content", "")).strip_edges()
    if content == "":
        content = str(message.get("thinking", "")).strip_edges()

    _save_raw_response(content)
    var parsed_result = _parse_any_model_output(content)

    if parsed_result == null and _retry_attempt < 1:
        _retry_attempt += 1
        var messages = _request_payload.get("messages", [])
        if messages.size() > 0:
            var first_message = messages[0]
            first_message["content"] = _build_line_retry_prompt()
            messages[0] = first_message
            _request_payload["messages"] = messages
        var options = _request_payload.get("options", {})
        options["num_predict"] = 160
        _request_payload["options"] = options
        call_deferred("_send_current_request", "The first response had no usable outfit tags; retrying once...")
        return

    if parsed_result == null:
        _finish_error("The vision model returned no usable outfit tags. The raw response was saved for troubleshooting")
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

func _parse_any_model_output(content):
    var cleaned = _strip_response_wrappers(content)
    if cleaned == "":
        return null

    var positive = []
    var negative = []
    var confidence = 0.5

    # First accept the old JSON-like response, including truncated arrays.
    positive = _clean_tag_list(_extract_string_list(cleaned, "positive_tags"))
    negative = _clean_tag_list(_extract_string_list(cleaned, "negative_tags"))
    if not positive.empty():
        confidence = clamp(_extract_number(cleaned, "confidence", 0.5), 0.0, 1.0)
        return _make_result(positive, negative, confidence)

    # Then parse the preferred labeled-line protocol and common variations.
    var section = ""
    var lines = cleaned.replace("\r", "\n").split("\n")
    for raw_line in lines:
        var line = str(raw_line).strip_edges()
        if line == "":
            continue

        var lower = line.to_lower()
        if _starts_with_any(lower, ["outfit:", "positive:", "positive tags:", "positive_tags:", "tags:"]):
            section = "positive"
            positive += _split_model_tags(_after_first_colon(line))
        elif _starts_with_any(lower, ["negative:", "negative tags:", "negative_tags:", "avoid:"]):
            section = "negative"
            negative += _split_model_tags(_after_first_colon(line))
        elif _starts_with_any(lower, ["confidence:", "score:"]):
            confidence = _parse_confidence(_after_first_colon(line), confidence)
            section = ""
        elif line.begins_with("-") or line.begins_with("*") or line.begins_with("•"):
            var bullet_text = line.substr(1).strip_edges()
            if section == "negative":
                negative += _split_model_tags(bullet_text)
            else:
                positive += _split_model_tags(bullet_text)
        elif section == "positive":
            positive += _split_model_tags(line)
        elif section == "negative":
            negative += _split_model_tags(line)

    positive = _dedupe_tags(positive, 30)
    negative = _dedupe_tags(negative, 20)
    if not positive.empty():
        return _make_result(positive, negative, confidence)

    # Last resort: models sometimes ignore labels but still return a clean list.
    positive = _fallback_plain_tags(cleaned)
    positive = _dedupe_tags(positive, 30)
    if positive.empty():
        return null
    return _make_result(positive, [], 0.35)

func _starts_with_any(text, prefixes):
    for prefix in prefixes:
        if text.begins_with(str(prefix)):
            return true
    return false

func _after_first_colon(text):
    var position = text.find(":")
    if position < 0:
        return text
    return text.substr(position + 1).strip_edges()

func _split_model_tags(text):
    var normalized = str(text).replace(";", "|").replace("•", "|")
    if normalized.find("|") < 0:
        normalized = normalized.replace(",", "|")

    var tags = []
    for raw_tag in normalized.split("|"):
        var tag = _clean_single_tag(raw_tag)
        if tag != "":
            tags.append(tag)
    return tags

func _clean_single_tag(value):
    var tag = str(value).strip_edges()
    while tag.begins_with("-") or tag.begins_with("*"):
        tag = tag.substr(1).strip_edges()
    while tag.ends_with(",") or tag.ends_with(".") or tag.ends_with(";"):
        tag = tag.substr(0, tag.length() - 1).strip_edges()
    if tag.begins_with('"') and tag.ends_with('"') and tag.length() > 1:
        tag = tag.substr(1, tag.length() - 2).strip_edges()
    if tag.length() > 120:
        return ""
    return tag

func _dedupe_tags(tags, maximum):
    var cleaned = []
    var seen = {}
    for raw_tag in tags:
        var tag = _clean_single_tag(raw_tag)
        var key = tag.to_lower()
        if tag == "" or seen.has(key):
            continue
        seen[key] = true
        cleaned.append(tag)
        if cleaned.size() >= maximum:
            break
    return cleaned

func _parse_confidence(text, default_value):
    var cleaned = str(text).strip_edges().replace("%", "")
    var number_text = ""
    var valid_characters = "0123456789."
    for index in range(cleaned.length()):
        var character = cleaned.substr(index, 1)
        if valid_characters.find(character) >= 0:
            number_text += character
        elif number_text != "":
            break
    if not number_text.is_valid_float():
        return default_value
    var value = float(number_text)
    if value > 1.0:
        value /= 100.0
    return clamp(value, 0.0, 1.0)

func _fallback_plain_tags(content):
    var candidate = str(content).strip_edges()
    candidate = candidate.replace("```json", "").replace("```", "")

    var tags = []
    for raw_line in candidate.replace("\r", "\n").split("\n"):
        var line = str(raw_line).strip_edges()
        if line == "":
            continue
        var lower = line.to_lower()
        if lower.begins_with("here") or lower.begins_with("the image") or lower.begins_with("i see") or lower.begins_with("description"):
            continue
        tags += _split_model_tags(_after_first_colon(line))

    # A single concise phrase is still more useful than a hard failure.
    if tags.empty() and candidate.length() <= 120:
        tags.append(candidate)
    return tags

func _make_result(positive, negative, confidence):
    return {
        "positive_tags": positive,
        "negative_tags": negative,
        "confidence": confidence,
        "summary": ""
    }

func _save_raw_response(content):
    var file = File.new()
    if file.open(LINE_RESPONSE_PATH, File.WRITE) == OK:
        file.store_string(str(content))
        file.close()
