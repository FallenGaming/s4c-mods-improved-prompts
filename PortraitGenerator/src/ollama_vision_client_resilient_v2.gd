extends "ollama_vision_client_resilient.gd"

# Final Godot 3.5 compatibility adjustments for retry payload mutation and
# PoolStringArray conversion.

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
