extends "outfit_vision_ui_line.gd"

# Invalidate cached results that may contain Qwen <think> reasoning prose and
# recognize compact item-name echoes such as ClothRobe or ClothPants.

func _build_equipment_signature(character):
    return "vision-no-think-v5|" + ._build_equipment_signature(character)

func _build_equipment_filter_sets(character):
    var filters = ._build_equipment_filter_sets(character)
    var worn_names = filters.get("worn_names", {})
    var raw_ids = filters.get("raw_ids", {})

    var worn_aliases = {}
    for name in worn_names.keys():
        var compact = _compact_equipment_token(name)
        if compact != "":
            worn_aliases[compact] = true
    for alias in worn_aliases.keys():
        worn_names[alias] = true

    var raw_aliases = {}
    for raw_id in raw_ids.keys():
        var compact_id = _compact_equipment_token(raw_id)
        if compact_id != "":
            raw_aliases[compact_id] = true
    for alias in raw_aliases.keys():
        raw_ids[alias] = true

    return {
        "worn_names": worn_names,
        "raw_ids": raw_ids
    }

func _compact_equipment_token(value):
    return str(value).to_lower().replace(" ", "").replace("_", "").replace("-", "").strip_edges()

func _sanitize_positive_analysis_tags(character, tags):
    var equipment_filters = _build_equipment_filter_sets(character)
    var worn_names = equipment_filters.worn_names
    var raw_ids = equipment_filters.raw_ids
    var cleaned = []
    var seen = {}

    if not (tags is Array):
        return cleaned

    for raw_tag in tags:
        var tag = _normalize_analysis_tag(raw_tag)
        var compact_tag = _compact_equipment_token(tag)
        if tag == "":
            continue
        if _looks_like_raw_metadata(tag):
            continue
        if _is_subject_or_body_tag(tag):
            continue
        if worn_names.has(tag) or worn_names.has(compact_tag):
            continue
        if raw_ids.has(tag) or raw_ids.has(compact_tag):
            continue
        if seen.has(tag):
            continue

        seen[tag] = true
        cleaned.append(tag)

    return cleaned
