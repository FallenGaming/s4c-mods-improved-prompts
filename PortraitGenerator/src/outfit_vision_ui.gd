extends Node

# Standalone UI/controller for local outfit analysis.
# This module discovers the existing PortraitGenerator panel at runtime instead of
# trying to extend an already-extended script, which the game's mod loader does not support.

const DEFAULT_VISION_URL = "http://127.0.0.1:11434"
const DEFAULT_VISION_MODEL = "qwen3-vl:4b"
const VISION_MAX_DIMENSION = 1024
const VISION_MIN_DIMENSION = 640
const LAST_CAPTURE_PATH = "user://portrait_generator_outfit_capture.png"

var _panel = null
var _prompt_popup = null
var _vision_client = null
var _util = null

var _vision_url_input = null
var _vision_model_input = null
var _analyze_button = null
var _reanalyze_button = null
var _status_label = null
var _vision_negative_tags = []

func update():
    _try_attach()

func _ready():
    _connect_client()
    call_deferred("_try_attach")

func _connect_client():
    _vision_client = modding_core.modules.PortraitGenerator_vision
    _util = modding_core.modules.PortraitGenerator_util
    if _vision_client == null:
        return
    if not _vision_client.is_connected("analysis_complete", self, "_on_analysis_complete"):
        _vision_client.connect("analysis_complete", self, "_on_analysis_complete")
    if not _vision_client.is_connected("analysis_error", self, "_on_analysis_error"):
        _vision_client.connect("analysis_error", self, "_on_analysis_error")
    if not _vision_client.is_connected("status_changed", self, "_on_analysis_status"):
        _vision_client.connect("status_changed", self, "_on_analysis_status")

func _try_attach():
    if _panel != null and is_instance_valid(_panel) and _prompt_popup != null and is_instance_valid(_prompt_popup):
        return

    _panel = null
    _prompt_popup = null

    if gui_controller == null or gui_controller.slavepanel == null:
        return
    var panel = gui_controller.slavepanel
    if not panel.has_node("PromptPanel"):
        return

    var popup = panel.get_node("PromptPanel")
    var left_path = "Panel/Margin/Outer/Scroll/Columns/LeftColumn"
    if not popup.has_node(left_path):
        return

    _panel = panel
    _prompt_popup = popup
    _connect_client()

    var left_col = popup.get_node(left_path)
    if left_col.has_node("OutfitVisionBox"):
        _bind_existing_controls(left_col.get_node("OutfitVisionBox"))
        return

    _inject_controls(left_col)

func _inject_controls(left_col):
    var clothing_row = left_col.get_node("ClothingRow")

    var box = VBoxContainer.new()
    box.set_name("OutfitVisionBox")

    var title = Label.new()
    title.set_text("AI outfit analysis (local Ollama)")
    box.add_child(title)

    var connection_row = HBoxContainer.new()
    box.add_child(connection_row)

    _vision_url_input = LineEdit.new()
    _vision_url_input.set_name("VisionUrlInput")
    _vision_url_input.set_custom_minimum_size(Vector2(230, 40))
    _vision_url_input.set_size_flags_horizontal(Control.SIZE_EXPAND_FILL)
    _vision_url_input.set_placeholder("Ollama URL")
    connection_row.add_child(_vision_url_input)

    _vision_model_input = LineEdit.new()
    _vision_model_input.set_name("VisionModelInput")
    _vision_model_input.set_custom_minimum_size(Vector2(170, 40))
    _vision_model_input.set_placeholder("Vision model")
    connection_row.add_child(_vision_model_input)

    var action_row = HBoxContainer.new()
    box.add_child(action_row)

    _analyze_button = Button.new()
    _analyze_button.set_name("AnalyzeOutfitBtn")
    _analyze_button.set_text("Analyze portrait + equipment")
    _analyze_button.set_size_flags_horizontal(Control.SIZE_EXPAND_FILL)
    _analyze_button.set_tooltip("Capture the displayed character and use equipped items as hints for a local vision model")
    _analyze_button.connect("pressed", self, "_on_analyze_pressed", [false])
    action_row.add_child(_analyze_button)

    _reanalyze_button = Button.new()
    _reanalyze_button.set_name("ReanalyzeOutfitBtn")
    _reanalyze_button.set_text("Reanalyze")
    _reanalyze_button.set_tooltip("Ignore the cached result and analyze the current image again")
    _reanalyze_button.connect("pressed", self, "_on_analyze_pressed", [true])
    action_row.add_child(_reanalyze_button)

    _status_label = Label.new()
    _status_label.set_name("VisionStatusLabel")
    _status_label.set_autowrap(true)
    box.add_child(_status_label)

    left_col.add_child(box)
    left_col.move_child(box, clothing_row.get_index() + 1)
    _load_settings()

func _bind_existing_controls(box):
    _vision_url_input = box.get_node_or_null("VisionUrlInput")
    _vision_model_input = box.get_node_or_null("VisionModelInput")
    _analyze_button = box.get_node_or_null("AnalyzeOutfitBtn")
    _reanalyze_button = box.get_node_or_null("ReanalyzeOutfitBtn")
    _status_label = box.get_node_or_null("VisionStatusLabel")

func _load_settings():
    var data = {}
    if _util != null:
        data = _util.read_settings()
    if _vision_url_input != null:
        _vision_url_input.set_text(str(data.get("vision_url", DEFAULT_VISION_URL)))
    if _vision_model_input != null:
        _vision_model_input.set_text(str(data.get("vision_model", DEFAULT_VISION_MODEL)))
    var saved_tags = data.get("vision_negative_tags", [])
    if saved_tags is Array:
        _vision_negative_tags = saved_tags
    else:
        _vision_negative_tags = []
    _set_status("Requires Ollama and qwen3-vl:4b. Results are cached per equipment combination.")

func _save_settings():
    if _util == null:
        return
    var data = _util.read_settings()
    if _vision_url_input != null:
        data["vision_url"] = _vision_url_input.text.strip_edges()
    if _vision_model_input != null:
        data["vision_model"] = _vision_model_input.text.strip_edges()
    data["vision_negative_tags"] = _vision_negative_tags
    _util.save_settings(data)

func _on_analyze_pressed(force_refresh):
    _try_attach()
    if _vision_client == null:
        _on_analysis_error("The Ollama vision module is unavailable")
        return
    if _vision_client.busy:
        _on_analysis_error("An outfit analysis is already running")
        return
    if _panel == null or not is_instance_valid(_panel):
        _on_analysis_error("The character panel is unavailable")
        return

    var character = input_handler.interacted_character
    if character == null:
        _on_analysis_error("No active character was found")
        return

    _save_settings()
    _set_buttons_disabled(true)
    _set_status("Capturing the displayed character...")

    var popup_was_visible = _prompt_popup != null and _prompt_popup.visible
    if popup_was_visible:
        _prompt_popup.hide()

    yield(get_tree(), "idle_frame")
    yield(get_tree(), "idle_frame")

    var image = _capture_displayed_character()

    if popup_was_visible and _prompt_popup != null and is_instance_valid(_prompt_popup):
        _prompt_popup.popup()

    if image == null:
        _set_buttons_disabled(false)
        _on_analysis_error("Could not capture the displayed character region")
        return

    image.save_png(LAST_CAPTURE_PATH)

    var model_name = _vision_model_input.text.strip_edges()
    var cache_key = model_name + "|" + _build_equipment_signature(character)
    _set_status("Analyzing outfit with %s..." % model_name)
    _vision_client.analyze_outfit(
        image,
        _build_equipment_context(character),
        cache_key,
        _vision_url_input.text,
        model_name,
        force_refresh
    )

func _capture_displayed_character():
    var viewport = _panel.get_viewport()
    if viewport == null or viewport.get_texture() == null:
        return _capture_body_texture_fallback()

    var screenshot = viewport.get_texture().get_data()
    if screenshot == null or screenshot.get_width() <= 0 or screenshot.get_height() <= 0:
        return _capture_body_texture_fallback()
    screenshot.flip_y()

    var target = _get_character_capture_control()
    if target == null:
        return _capture_body_texture_fallback()

    var rect = target.get_global_rect()
    var logical_size = viewport.get_visible_rect().size
    if logical_size.x <= 0 or logical_size.y <= 0:
        return _capture_body_texture_fallback()

    var scale_x = float(screenshot.get_width()) / logical_size.x
    var scale_y = float(screenshot.get_height()) / logical_size.y
    var padding = 8
    var x = int(floor(rect.position.x * scale_x)) - padding
    var y = int(floor(rect.position.y * scale_y)) - padding
    var width = int(ceil(rect.size.x * scale_x)) + padding * 2
    var height = int(ceil(rect.size.y * scale_y)) + padding * 2

    x = int(clamp(x, 0, max(0, screenshot.get_width() - 1)))
    y = int(clamp(y, 0, max(0, screenshot.get_height() - 1)))
    width = int(min(width, screenshot.get_width() - x))
    height = int(min(height, screenshot.get_height() - y))
    if width < 16 or height < 16:
        return _capture_body_texture_fallback()

    return _prepare_vision_image(screenshot.get_rect(Rect2(x, y, width, height)))

func _get_character_capture_control():
    if _panel == null:
        return null
    var body_module = _panel.BodyModule
    if body_module == null:
        return null
    var body_node = body_module.get_node_or_null("Body")
    if body_node != null and body_node is Control:
        return body_node
    if body_module is Control:
        return body_module
    return null

func _capture_body_texture_fallback():
    if _panel == null or _panel.BodyModule == null:
        return null
    var body_node = _panel.BodyModule.get_node_or_null("Body")
    if body_node == null:
        return null

    var texture = body_node.get("texture")
    if texture == null or not texture.has_method("get_data"):
        return null
    return _prepare_vision_image(texture.get_data())

func _prepare_vision_image(image):
    if image == null or image.get_width() <= 0 or image.get_height() <= 0:
        return null

    var prepared = image.duplicate()
    if prepared.is_compressed() and prepared.decompress() != OK:
        return null
    if prepared.get_format() != Image.FORMAT_RGB8 and prepared.get_format() != Image.FORMAT_RGBA8:
        prepared.convert(Image.FORMAT_RGBA8)

    var largest = max(prepared.get_width(), prepared.get_height())
    var target_largest = largest
    var interpolation = Image.INTERPOLATE_LANCZOS
    if largest > VISION_MAX_DIMENSION:
        target_largest = VISION_MAX_DIMENSION
    elif largest < VISION_MIN_DIMENSION:
        target_largest = VISION_MIN_DIMENSION
        interpolation = Image.INTERPOLATE_NEAREST

    if target_largest != largest:
        var ratio = float(target_largest) / float(largest)
        prepared.resize(
            max(1, int(round(prepared.get_width() * ratio))),
            max(1, int(round(prepared.get_height() * ratio))),
            interpolation
        )
    return prepared

func _format_item_parts(item):
    var parts = []
    var part_keys = item.parts.keys()
    part_keys.sort()
    for part_key in part_keys:
        parts.append("%s=%s" % [str(part_key), str(item.parts[part_key])])
    return ", ".join(parts)

func _build_equipment_context(character):
    var gear = character.equipment.gear
    var slot_order = ['chest', 'hands', 'head', 'neck', 'legs', 'rhand', 'lhand', 'underwear', 'ass', 'crotch']
    var lines = []
    var seen_item_ids = {}

    for slot in slot_order:
        var item_id = gear.get(slot, null)
        if item_id == null or seen_item_ids.has(item_id):
            continue
        seen_item_ids[item_id] = true
        var item = ResourceScripts.game_res.items[item_id]
        lines.append("- slot=%s; name=%s; base_id=%s; code=%s; crafting_parts={%s}" % [
            slot,
            str(item.name),
            str(item.itembase),
            str(item.code),
            _format_item_parts(item)
        ])

    if lines.empty():
        return "- no equipped items"
    return "\n".join(lines)

func _build_equipment_signature(character):
    var gear = character.equipment.gear
    var slot_order = ['chest', 'hands', 'head', 'neck', 'legs', 'rhand', 'lhand', 'underwear', 'ass', 'crotch']
    var components = [
        "sex=%s" % str(character.get_stat('sex')),
        "race=%s" % str(character.get_stat('race')),
        "body_image=%s" % str(character.get_stat('body_image'))
    ]
    var seen_item_ids = {}

    for slot in slot_order:
        var item_id = gear.get(slot, null)
        if item_id == null or seen_item_ids.has(item_id):
            continue
        seen_item_ids[item_id] = true
        var item = ResourceScripts.game_res.items[item_id]
        components.append("%s=%s:%s:%s" % [slot, str(item.itembase), str(item.name), _format_item_parts(item)])
    return "|".join(components)

func _get_clothing_input():
    if _prompt_popup == null:
        return null
    var row = _prompt_popup.get_node_or_null("Panel/Margin/Outer/Scroll/Columns/LeftColumn/ClothingRow")
    if row == null:
        return null
    for child in row.get_children():
        if child.has_method("set_text") and child.has_method("get_text"):
            return child
    return null

func _get_negative_input():
    if _prompt_popup == null:
        return null
    var left_col = _prompt_popup.get_node_or_null("Panel/Margin/Outer/Scroll/Columns/LeftColumn")
    if left_col == null or not left_col.has_node("NegativeLabel"):
        return null
    var start_index = left_col.get_node("NegativeLabel").get_index() + 1
    for index in range(start_index, left_col.get_child_count()):
        var child = left_col.get_child(index)
        if child.has_method("set_text") and child.has_method("get_text"):
            return child
        if child.get_name() == "GeneratePromptsBtn":
            break
    return null

func _on_analysis_complete(result, from_cache):
    _set_buttons_disabled(false)

    var clothing_input = _get_clothing_input()
    if clothing_input == null:
        _on_analysis_error("Could not find the Clothing description input")
        return

    clothing_input.set_text(", ".join(result.get("positive_tags", [])))
    _replace_vision_negative_tags(result.get("negative_tags", []))

    if _panel != null and _panel.has_method("_generate_prompts"):
        _panel.call("_generate_prompts", true)

    var source_text = "cached"
    if not from_cache:
        source_text = "new"
    var confidence = int(round(float(result.get("confidence", 0.0)) * 100.0))
    var status = "Applied %s analysis (%d%% confidence)" % [source_text, confidence]
    var summary = str(result.get("summary", "")).strip_edges()
    if summary != "":
        status += ": " + summary
    _set_status(status)
    _save_settings()

func _replace_vision_negative_tags(tags):
    var negative_input = _get_negative_input()
    if negative_input == null or not (tags is Array):
        return

    var previous = {}
    for old_tag in _vision_negative_tags:
        previous[str(old_tag).strip_edges().to_lower()] = true

    var combined = []
    var seen = {}
    for entry in negative_input.get_text().split(","):
        var existing_tag = str(entry).strip_edges()
        var existing_key = existing_tag.to_lower()
        if existing_tag == "" or previous.has(existing_key) or seen.has(existing_key):
            continue
        seen[existing_key] = true
        combined.append(existing_tag)

    _vision_negative_tags = []
    for entry in tags:
        var tag = str(entry).strip_edges()
        var key = tag.to_lower()
        if tag == "" or seen.has(key):
            continue
        seen[key] = true
        combined.append(tag)
        _vision_negative_tags.append(tag)

    negative_input.set_text(", ".join(combined))

func _on_analysis_status(message):
    _set_status(message)

func _on_analysis_error(message):
    _set_buttons_disabled(false)
    _set_status("Vision error: " + str(message))
    print("[PortraitGenerator][OutfitVision] %s" % str(message))

func _set_status(message):
    if _status_label != null:
        _status_label.set_text(str(message))

func _set_buttons_disabled(disabled):
    if _analyze_button != null:
        _analyze_button.set_disabled(disabled)
    if _reanalyze_button != null:
        _reanalyze_button.set_disabled(disabled)
