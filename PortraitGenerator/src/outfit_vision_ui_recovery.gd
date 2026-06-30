extends "outfit_vision_ui_filtered.gd"

# Force a fresh analysis after the JSON-recovery client update instead of reusing
# results produced by earlier captioning rules.

func _build_equipment_signature(character):
    return "vision-json-recovery-v3|" + ._build_equipment_signature(character)
