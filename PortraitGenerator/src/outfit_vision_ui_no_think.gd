extends "outfit_vision_ui_line.gd"

# Invalidate cached results that may contain Qwen <think> reasoning prose.

func _build_equipment_signature(character):
    return "vision-no-think-v5|" + ._build_equipment_signature(character)
