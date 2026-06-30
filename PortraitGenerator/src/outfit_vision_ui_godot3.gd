extends "outfit_vision_ui.gd"

# Godot 3.5 compatibility layer for the dynamically-created analyzer controls.
# Godot 3 uses Control.set_h_size_flags() rather than the Godot 4-style
# set_size_flags_horizontal() method.

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
    _vision_url_input.set_h_size_flags(Control.SIZE_EXPAND_FILL)
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
    _analyze_button.set_h_size_flags(Control.SIZE_EXPAND_FILL)
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
