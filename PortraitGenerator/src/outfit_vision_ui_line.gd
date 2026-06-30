extends "outfit_vision_ui_recovery.gd"

# Invalidate earlier JSON-based cache entries after switching to the line protocol.

func _build_equipment_signature(character):
    return "vision-line-protocol-v4|" + ._build_equipment_signature(character)
