extends "extended_CharInfoMainModule.gd"

# Adds local AI outfit analysis to the existing PortraitGenerator panel without
# modifying the large base extension script. The displayed character region is
# captured, paired with equipped-item metadata, and sent to Ollama.

const DEFAULT_VISION_URL = "http://127.0.0.1:11434"
const DEFAULT_VISION_MODEL = "qwen3-vl:4b"
const VISION_MAX_DIMENSION = 1024
const VISION_MIN_DIMENSION = 640
const LAST_CAPTURE_PATH = "user://portrait_generator_outfit_capture.png"

var outfit_vision_client = null
var vision_url_input = null
var vision_model_input = null
var vision_analyze_button = null
var vision_reanalyze_button = null
var vision_status_label = null
var _vision_negative_tags = []

func _ready():
    ._ready()
    call_deferred("_setup_outfit_vision")

func _setup_outfit_vision():
    if prompt_popup == null or prompt_popup.has_node("Panel/Margin/Outer/Scroll/Columns/LeftColumn/OutfitVisionBox"):
        return

    if util == null:
        util = modding_core.modules.PortraitGenerator_util

    outfit_vision_client = modding_core.modules.PortraitGenerator_vision
    if outfit_vision_client != null:
        var old_parent = outfit_vision_client.get_parent()
        if old_parent != null and old_parent != self:
            old_parent.remove_child(outfit_vision_client)
        if outfit_vision_client.get_parent() == null:
            add_child(outfit_vision_client)
        if not outfit_vision_client.is_connected("analysis_complete", self, "_on_outfit_analysis_complete"):
            outfit_vision_client.connect("analysis_complete", self, "_on_outfit_analysis_complete")
        if not outfit_vision_client.is_connected("analysis_error", self, "_on_outfit_analysis_error"):
            outfit_vision_client.connect("analysis_error", self, "_on_outfit_analysis_error")
        if not outfit_vision_client.is_connected("status_changed", self, "_on_outfit_analysis_status"):
            outfit_vision_client.connect("status_changed", self, "_on_outfit_analysis_status")

    var left_col = prompt_popup.get_node("Panel/Margin/Outer/Scroll/Columns/LeftColumn")
    var clothing_row = left_col.get_node("ClothingRow")

    var box = VBoxContainer.new()
    box.set_name("OutfitVisionBox")
    box.set_custom_minimum_size(Vector2(0, 0))

    var title = Label.new()
    title.set_text("AI outfit analysis (local Ollama)")
    box.add_child(title)

    var connection_row = HBoxContainer.new()
    box.add_child(connection_row)

    vision_url_input = LineEdit.new()
    vision_url_input.set_name("VisionUrlInput")
    vision_url_input.set_custom_minimum_size(Vector2(230, 40))
    vision_url_input.set_size_flags_horizontal(Control.SIZE_EXPAND_FILL)
    vision_url_input.set_placeholder("Ollama URL")
    vision_url_input.set_text(DEFAULT_VISION_URL)
    connection_row.add_child(vision_url_input)

    vision_model_input = LineEdit.new()
    vision_model_input.set_name("VisionModelInput")
    vision_model_input.set_custom_minimum_size(Vector2(170, 40))
    vision_model_input.set_placeholder("Vision model")
    vision_model_input.set_text(DEFAULT_VISION_MODEL)
    connection_row.add_child(vision_model_input)

    var action_row = HBoxContainer.new()
    box.add_child(action_row)

    vision_analyze_button = Button.new()
    vision_analyze_button.set_name("AnalyzeOutfitBtn")
    vision_analyze_button.set_text("Analyze portrait + equipment")
    vision_analyze_button.set_size_flags_horizontal(Control.SIZE_EXPAND_FILL)
    vision_analyze_button.set_tooltip("Capture the displayed character and use the equipped items as hints for a local vision model")
    vision_analyze_button.connect("pressed", self, "_on_analyze_outfit_pressed", [false])
    action_row.add_child(vision_analyze_button)

    vision_reanalyze_button = Button.new()
    vision_reanalyze_button.set_name("ReanalyzeOutfitBtn")
    vision_reanalyze_button.set_text("Reanalyze")
    vision_reanalyze_button.set_tooltip("Ignore the cached result and analyze the current image again")
    vision_reanalyze_button.connect("pressed", self, "_on_analyze_outfit_pressed", [true])
    action_row.add_child(vision_reanalyze_button)

    vision_status_label = Label.new()
    vision_status_label.set_name("VisionStatusLabel")
    vision_status_label.set_autowrap(true)
    vision_status_label.set_text("Requires Ollama and qwen3-vl:4b. Results are cached per equipment combination.")
    box.add_child(vision_status_label)

    left_col.add_child(box)
    left_col.move_child(box, clothing_row.get_index() + 1)
    _load_ui_settings()
    call_deferred("_sync_all_exp_inputs")

func _save_ui_settings():
    ._save_ui_settings()
    if util == null or vision_url_input == null or vision_model_input == null:
        return
    var data = util.read_settings()
    data["vision_url"] = vision_url_input.text.strip_edges()
    data["vision_model"] = vision_model_input.text.strip_edges()
    data["vision_negative_tags"] = _vision_negative_tags
    util.save_settings(data)

func _load_ui_settings():
    ._load_ui_settings()
    if util == null or vision_url_input == null or vision_model_input == null:
        return
    var data = util.read_settings()
    vision_url_input.set_text(str(data.get("vision_url", DEFAULT_VISION_URL)))
    vision_model_input.set_text(str(data.get("vision_model", DEFAULT_VISION_MODEL)))
    var saved_negative_tags = data.get("vision_negative_tags", [])
    _vision_negative_tags = saved_negative_tags if saved_negative_tags is Array else []

func _on_analyze_outfit_pressed(force_refresh):
    if outfit_vision_client == null:
        _on_outfit_analysis_error("The Ollama vision module is unavailable")
        return
    if outfit_vision_client.busy:
        _on_outfit_analysis_error("An outfit analysis is already running")
        return

    active_person = input_handler.interacted_character
    if active_person == null:
        _on_outfit_analysis_error("No active character was found")
        return

    _save_ui_settings()
    _set_vision_buttons_disabled(true)
    _on_outfit_analysis_status("Capturing the displayed character...")

    var popup_was_visible = prompt_popup != null and prompt_popup.visible
    if popup_was_visible:
        prompt_popup.hide()

    # Wait for the popup to leave the rendered frame before taking the screenshot.
    yield(get_tree(), "idle_frame")
    yield(get_tree(), "idle_frame")

    var image = _capture_displayed_character()

    if popup_was_visible:
        prompt_popup.popup()
        call_deferred("_sync_all_exp_inputs")

    if image == null:
        _set_vision_buttons_disabled(false)
        _on_outfit_analysis_error("Could not capture the displayed character region")
        return

    # Keep the most recent crop so the user can verify exactly what the model saw.
    image.save_png(LAST_CAPTURE_PATH)

    var equipment_context = _build_equipment_context(active_person)
    var model_name = vision_model_input.text.strip_edges()
    var cache_key = model_name + "|" + _build_equipment_signature(active_person)
    _on_outfit_analysis_status("Analyzing outfit with %s..." % model_name)
    outfit_vision_client.analyze_outfit(
        image,
        equipment_context,
        cache_key,
        vision_url_input.text,
        model_name,
        force_refresh
    )

func _capture_displayed_character():
    var viewport = get_viewport()
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
    var logical_size = get_viewport_rect().size
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

    var cropped = screenshot.get_rect(Rect2(x, y, width, height))
    return _prepare_vision_image(cropped)

func _get_character_capture_control():
    if gui_controller == null or gui_controller.slavepanel == null:
        return null
    var body_module = gui_controller.slavepanel.BodyModule
    if body_module == null:
        return null

    var body_node = body_module.get_node_or_null("Body")
    if body_node != null and body_node is Control:
        return body_node
    if body_module is Control:
        return body_module
    return null

func _capture_body_texture_fallback():
    if gui_controller == null or gui_controller.slavepanel == null:
        return null
    var body_module = gui_controller.slavepanel.BodyModule
    if body_module == null:
        return null
    var body_node = body_module.get_node_or_null("Body")
    if body_node == null:
        return null

    var texture = null
    if body_node.has_method("get_texture"):
        texture = body_node.get_texture()
    else:
        texture = body_node.get("texture")
    if texture == null or not texture.has_method("get_data"):
        return null

    var image = texture.get_data()
    if image == null:
        return null
    return _prepare_vision_image(image)

func _prepare_vision_image(image):
    if image == null or image.get_width() <= 0 or image.get_height() <= 0:
        return null

    var prepared = image.duplicate()
    if prepared.is_compressed():
        if prepared.decompress() != OK:
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
        var new_width = max(1, int(round(prepared.get_width() * ratio)))
        var new_height = max(1, int(round(prepared.get_height() * ratio)))
        prepared.resize(new_width, new_height, interpolation)
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

func _on_outfit_analysis_complete(result, from_cache):
    _set_vision_buttons_disabled(false)

    var positive_tags = result.get("positive_tags", [])
    var negative_tags = result.get("negative_tags", [])
    clothing_input.set_text(", ".join(positive_tags))
    _replace_vision_negative_tags(negative_tags)
    _generate_prompts(true)

    var confidence = int(round(float(result.get("confidence", 0.0)) * 100.0))
    var source_text = "cached" if from_cache else "new"
    var summary = str(result.get("summary", "")).strip_edges()
    var status = "Applied %s analysis (%d%% confidence)" % [source_text, confidence]
    if summary != "":
        status += ": " + summary
    _on_outfit_analysis_status(status)

func _replace_vision_negative_tags(tags):
    if negative_input == null or not (tags is Array):
        return

    var previous = {}
    for old_tag in _vision_negative_tags:
        previous[str(old_tag).strip_edges().to_lower()] = true

    var combined = []
    var seen = {}
    for entry in negative_input.text.split(","):
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

func _on_outfit_analysis_status(message):
    if vision_status_label != null:
        vision_status_label.set_text(str(message))

func _on_outfit_analysis_error(message):
    _set_vision_buttons_disabled(false)
    _on_outfit_analysis_status("Vision error: " + str(message))
    print("[PortraitGenerator][OutfitVision] %s" % str(message))

func _set_vision_buttons_disabled(disabled):
    if vision_analyze_button != null:
        vision_analyze_button.set_disabled(disabled)
    if vision_reanalyze_button != null:
        vision_reanalyze_button.set_disabled(disabled)
