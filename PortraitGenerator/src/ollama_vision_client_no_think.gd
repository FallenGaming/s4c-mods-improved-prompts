extends "ollama_vision_client_line.gd"

# Qwen can emit hidden reasoning inside <think> tags even when think=false.
# Never treat that reasoning as prompt tags.

const NO_THINK_RESPONSE_PATH = "user://portrait_generator_last_vision_response.txt"

var _last_equipment_context = ""

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

    _last_equipment_context = str(equipment_context)
    _request_server_url = server_url
    _request_payload = {
        "model": model_name,
        "stream": false,
        "think": false,
        "keep_alive": 0,
        "options": {
            "temperature": 0,
            "num_predict": 220
        },
        "messages": [
            {
                "role": "system",
                "content": "You are a visual tag extractor. Never reveal reasoning. Return only the exact labeled output requested by the user."
            },
            {
                "role": "user",
                "content": _build_no_think_prompt(equipment_context),
                "images": [Marshalls.raw_to_base64(png_data)]
            }
        ]
    }

    _retry_attempt = 0
    _pending_cache_key = cache_key
    busy = true
    _send_current_request("Sending character image to Ollama...")

func _build_no_think_prompt(equipment_context):
    return """/no_think
Do not reason, explain, or describe your process.

Inspect the attached fantasy-game character image.

Equipment hints:
%s

Describe ONLY visible clothing, armor, accessories, footwear, and held equipment. Use the equipment list only as a hint. Determine garment shape, colors, coverage, layers, and trim from the image.

Never describe hair, eyes, skin, face, body shape, height, breasts, hips, pose, camera framing, background, art style, raw item IDs, slot names, or crafting fields. Crafting materials do not recolor clothing. A visible held item such as a wooden club is allowed.

Return exactly these three lines and nothing else:
OUTFIT: short visual tag | short visual tag | short visual tag
NEGATIVE: likely clothing misread | likely clothing misread
CONFIDENCE: 0.90

Use no more than 20 OUTFIT tags and 10 NEGATIVE tags.""" % equipment_context

func _build_no_think_retry_prompt():
    return """/no_think
Do not think aloud. Do not explain.
Look only at the attached image and return exactly one line:
OUTFIT: visible clothing tag | visible clothing tag | held equipment tag
Do not include JSON, markdown, body traits, camera terms, IDs, slots, or crafting data."""

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
    var raw_content = str(message.get("content", "")).strip_edges()
    _save_no_think_response(raw_content)

    # Never fall back to message.thinking. It is internal reasoning, not output.
    var final_content = _remove_reasoning_blocks(raw_content)
    var parsed_result = _parse_strict_model_output(final_content)

    if parsed_result == null and _retry_attempt < 1:
        _retry_attempt += 1
        var messages = _request_payload.get("messages", [])
        if messages.size() >= 2:
            var user_message = messages[1]
            user_message["content"] = _build_no_think_retry_prompt()
            messages[1] = user_message
            _request_payload["messages"] = messages
        var options = _request_payload.get("options", {})
        options["num_predict"] = 180
        _request_payload["options"] = options
        call_deferred("_send_current_request", "The model returned reasoning instead of tags; retrying without thinking...")
        return

    if parsed_result == null:
        parsed_result = _equipment_context_fallback(_last_equipment_context)

    if parsed_result == null:
        _finish_error("The vision model returned reasoning instead of outfit tags. The raw response was saved for troubleshooting")
        return

    if _pending_cache_key != "":
        _cache[_pending_cache_key] = parsed_result
        _save_cache()

    _pending_cache_key = ""
    _request_payload = {}
    _request_server_url = ""
    _retry_attempt = 0
    _last_equipment_context = ""
    busy = false
    emit_signal("status_changed", "Outfit analysis complete")
    emit_signal("analysis_complete", parsed_result, false)

func _remove_reasoning_blocks(content):
    var cleaned = str(content).strip_edges()
    cleaned = _remove_named_block(cleaned, "<think>", "</think>")
    cleaned = _remove_named_block(cleaned, "<analysis>", "</analysis>")
    return cleaned.strip_edges()

func _remove_named_block(content, open_tag, close_tag):
    var cleaned = str(content)
    while true:
        var start = cleaned.find(open_tag)
        if start < 0:
            break
        var finish = cleaned.find(close_tag, start + open_tag.length())
        if finish < 0:
            # An unclosed reasoning block means everything after it is reasoning.
            cleaned = cleaned.substr(0, start)
            break
        cleaned = cleaned.substr(0, start) + cleaned.substr(finish + close_tag.length())
    return cleaned

func _parse_strict_model_output(content):
    var cleaned = _strip_response_wrappers(content)
    if cleaned == "":
        return null

    var positive = []
    var negative = []
    var confidence = 0.5

    # Retain compatibility with earlier JSON-like responses.
    positive = _clean_tag_list(_extract_string_list(cleaned, "positive_tags"))
    negative = _clean_tag_list(_extract_string_list(cleaned, "negative_tags"))
    positive = _filter_compact_tags(positive, 24)
    negative = _filter_compact_tags(negative, 16)
    if not positive.empty():
        confidence = clamp(_extract_number(cleaned, "confidence", 0.5), 0.0, 1.0)
        return _make_result(positive, negative, confidence)

    var section = ""
    for raw_line in cleaned.replace("\r", "\n").split("\n"):
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
            var bullet = line.substr(1).strip_edges()
            if section == "negative":
                negative += _split_model_tags(bullet)
            elif section == "positive" or _looks_like_compact_tag(bullet):
                positive += _split_model_tags(bullet)
        elif section == "positive":
            positive += _split_model_tags(line)
        elif section == "negative":
            negative += _split_model_tags(line)

    positive = _filter_compact_tags(positive, 24)
    negative = _filter_compact_tags(negative, 16)
    if not positive.empty():
        return _make_result(positive, negative, confidence)

    # Accept an unlabeled compact tag list, but never prose or reasoning.
    if cleaned.length() <= 240 and cleaned.find("|") >= 0:
        positive = _filter_compact_tags(_split_model_tags(cleaned), 24)
    elif cleaned.length() <= 180 and cleaned.find(",") >= 0 and not _looks_like_reasoning(cleaned):
        positive = _filter_compact_tags(_split_model_tags(cleaned), 24)

    if positive.empty():
        return null
    return _make_result(positive, [], 0.35)

func _filter_compact_tags(tags, maximum):
    var cleaned = []
    var seen = {}
    for raw_tag in tags:
        var tag = _clean_single_tag(raw_tag)
        var key = tag.to_lower()
        if tag == "" or seen.has(key):
            continue
        if not _looks_like_compact_tag(tag):
            continue
        seen[key] = true
        cleaned.append(tag)
        if cleaned.size() >= maximum:
            break
    return cleaned

func _looks_like_compact_tag(value):
    var tag = str(value).strip_edges()
    if tag == "" or tag.length() > 80:
        return false
    if tag.find("<think>") >= 0 or tag.find("</think>") >= 0 or tag.find("<analysis>") >= 0:
        return false
    if _looks_like_reasoning(tag):
        return false

    var words = tag.replace("-", " ").replace("_", " ").split(" ", false)
    return words.size() <= 8

func _looks_like_reasoning(value):
    var text = " " + str(value).strip_edges().to_lower() + " "
    var markers = [
        " let's ",
        " let us ",
        " i need ",
        " i should ",
        " i can ",
        " the character ",
        " the user ",
        " the image ",
        " equipment hints ",
        " for example ",
        " because ",
        " so the ",
        " should be ",
        " would be ",
        " problem says ",
        " as per ",
        " first, ",
        " then ",
        " possible negatives ",
        " list possible "
    ]
    for marker in markers:
        if text.find(marker) >= 0:
            return true
    return false

func _equipment_context_fallback(context):
    var tags = []
    var seen = {}

    for raw_line in str(context).replace("\r", "\n").split("\n"):
        var line = str(raw_line).strip_edges()
        if line == "" or line.find("name=") < 0:
            continue

        var slot = _context_field(line, "slot")
        var item_name = _context_field(line, "name")
        if item_name == "":
            continue

        var fallback_tag = item_name.to_lower().strip_edges()
        if slot == "chest" or slot == "legs" or slot == "underwear" or slot == "ass" or slot == "crotch":
            fallback_tag = _strip_material_prefix(fallback_tag)

        if fallback_tag == "" or seen.has(fallback_tag):
            continue
        seen[fallback_tag] = true
        tags.append(fallback_tag)

    if tags.empty():
        return null
    return _make_result(tags, [], 0.2)

func _context_field(line, field_name):
    var marker = field_name + "="
    var start = line.find(marker)
    if start < 0:
        return ""
    start += marker.length()
    var finish = line.find(";", start)
    if finish < 0:
        finish = line.length()
    return line.substr(start, finish - start).strip_edges()

func _strip_material_prefix(item_name):
    var result = str(item_name).strip_edges()
    var prefixes = ["cloth ", "leather ", "wooden ", "wood ", "iron ", "steel ", "copper ", "bronze ", "silver ", "gold "]
    for prefix in prefixes:
        if result.begins_with(prefix):
            return result.substr(str(prefix).length()).strip_edges()
    return result

func _save_no_think_response(content):
    var file = File.new()
    if file.open(NO_THINK_RESPONSE_PATH, File.WRITE) == OK:
        file.store_string(str(content))
        file.close()
