extends "ollama_vision_client_resilient.gd"

# Final Godot 3.5 compatibility adjustments for cache recovery, retry payload
# mutation, and PoolStringArray conversion.

func _ready():
    _load_cache_safely()
    _http = HTTPRequest.new()
    _http.connect("request_completed", self, "_on_request_completed")
    add_child(_http)

func _load_cache_safely():
    var file = File.new()
    if not file.file_exists(CACHE_PATH):
        _cache = {}
        return
    if file.open(CACHE_PATH, File.READ) != OK:
        _cache = {}
        return

    var cache_text = file.get_as_text()
    file.close()

    # JSON.parse logs its own engine error for truncated files. Check common
    # corruption first so an interrupted cache write can be reset quietly.
    if not _looks_like_complete_json(cache_text):
        print("[PortraitGenerator][OutfitVision] Outfit cache was incomplete and has been reset")
        _cache = {}
        _reset_cache_file()
        return

    var parsed = JSON.parse(cache_text)
    if parsed.error == OK and parsed.result is Dictionary:
        _cache = parsed.result
    else:
        _cache = {}
        _reset_cache_file()

func _looks_like_complete_json(text):
    var cleaned = str(text).strip_edges()
    if cleaned == "" or not cleaned.begins_with("{") or not cleaned.ends_with("}"):
        return false

    var in_string = false
    var escaped = false
    var brace_depth = 0
    var bracket_depth = 0

    for index in range(cleaned.length()):
        var character = cleaned.substr(index, 1)
        if in_string:
            if escaped:
                escaped = false
            elif character == "\\":
                escaped = true
            elif character == '"':
                in_string = false
        else:
            match character:
                '"':
                    in_string = true
                "{":
                    brace_depth += 1
                "}":
                    brace_depth -= 1
                    if brace_depth < 0:
                        return false
                "[":
                    bracket_depth += 1
                "]":
                    bracket_depth -= 1
                    if bracket_depth < 0:
                        return false

    return not in_string and not escaped and brace_depth == 0 and bracket_depth == 0

func _reset_cache_file():
    var file = File.new()
    if file.open(CACHE_PATH, File.WRITE) == OK:
        file.store_string("{}")
        file.close()

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
    var parsed_result = _parse_structured_content(content)

    if parsed_result == null:
        _save_invalid_response(content)
        if _retry_attempt < 1:
            _retry_attempt += 1

            var messages = _request_payload.get("messages", [])
            if messages.size() > 0:
                var first_message = messages[0]
                first_message["content"] = _build_retry_prompt()
                messages[0] = first_message
                _request_payload["messages"] = messages

            var options = _request_payload.get("options", {})
            options["num_predict"] = 256
            _request_payload["options"] = options

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
        var values = []
        for part in str(one_value).split(","):
            values.append(part)
        return values
    return []
