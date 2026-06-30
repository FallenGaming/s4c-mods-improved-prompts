extends "outfit_vision_ui_godot3.gd"

# Cleans VLM output before it reaches Clothing description. The model sees both the
# image and game metadata, so it can occasionally echo character tags or raw fields.

const ANALYSIS_RULESET_VERSION = "outfit-tags-v2"

var _OUTFIT_SLOT_ORDER = ['chest', 'hands', 'head', 'neck', 'legs', 'rhand', 'lhand', 'underwear', 'ass', 'crotch']
var _WORN_EQUIPMENT_SLOTS = ['chest', 'legs', 'underwear', 'ass', 'crotch']

var _NON_OUTFIT_EXACT_TAGS = {
    '1girl': true,
    '1boy': true,
    'solo': true,
    'girl': true,
    'boy': true,
    'woman': true,
    'man': true,
    'female': true,
    'male': true,
    'adult woman': true,
    'adult man': true,
    'young adult woman': true,
    'young adult female': true,
    'young adult man': true,
    'young adult male': true,
    'cowboy shot': true,
    'portrait': true,
    'upper body': true,
    'full body': true,
    'medium shot': true,
    'close-up': true,
    'closeup': true,
    'clothed': true,
    'nude': true,
    'very short': true,
    'short stature': true,
    'average height': true,
    'tall': true,
    'petite': true,
    'slender': true,
    'average build': true,
    'curvy': true,
    'wide hips': true,
    'very wide hips': true,
    'narrow hips': true,
    'broad hips': true,
    'curvy hips': true,
    'thick thighs': true,
    'anime': true,
    '2d': true,
    'game sprite': true
}

var _NON_OUTFIT_BODY_WORDS = {
    'hair': true,
    'ponytail': true,
    'pigtail': true,
    'pigtails': true,
    'braid': true,
    'braids': true,
    'bun': true,
    'eye': true,
    'eyes': true,
    'pupil': true,
    'pupils': true,
    'skin': true,
    'face': true,
    'facial': true,
    'beard': true,
    'mustache': true,
    'breast': true,
    'breasts': true,
    'height': true
}

var _RAW_METADATA_MARKERS = [
    'armorbase',
    'armortrim',
    'armorenc',
    'armorcloth',
    'weaponmace',
    'weaponhandle',
    'weaponenc',
    'toolhandle',
    'toolblade',
    'toolclothwork',
    'partmaterialname',
    'crafting_parts',
    'base_id',
    'itembase'
]

func _build_equipment_signature(character):
    # Invalidates older cached captions so the stricter prompt is used immediately.
    return ANALYSIS_RULESET_VERSION + '|' + ._build_equipment_signature(character)

func _normalize_analysis_tag(value):
    var tag = str(value).replace('\n', ' ').replace('\r', ' ').strip_edges().to_lower()

    while tag.begins_with('-'):
        tag = tag.substr(1).strip_edges()
    while tag.ends_with(',') or tag.ends_with('.') or tag.ends_with(';'):
        tag = tag.substr(0, tag.length() - 1).strip_edges()

    if tag.begins_with('(') and tag.ends_with(')') and tag.length() > 2:
        tag = tag.substr(1, tag.length() - 2).strip_edges()

    var weight_separator = tag.find(':')
    if weight_separator > 0:
        var possible_weight = tag.substr(weight_separator + 1).strip_edges()
        if possible_weight.is_valid_float():
            tag = tag.substr(0, weight_separator).strip_edges()

    while tag.find('  ') >= 0:
        tag = tag.replace('  ', ' ')
    return tag

func _tag_words(tag):
    var words_text = tag
    for separator in ['(', ')', '[', ']', '{', '}', ':', ',', ';', '/', '_', '-']:
        words_text = words_text.replace(separator, ' ')
    return words_text.split(' ', false)

func _is_subject_or_body_tag(tag):
    if _NON_OUTFIT_EXACT_TAGS.has(tag):
        return true

    for word in _tag_words(tag):
        if _NON_OUTFIT_BODY_WORDS.has(str(word)):
            return true
    return false

func _looks_like_raw_metadata(tag):
    if tag.find('=') >= 0:
        return true
    var compact = tag.replace(' ', '').replace('_', '').to_lower()
    for marker in _RAW_METADATA_MARKERS:
        if compact.find(marker) >= 0:
            return true
    return false

func _build_equipment_filter_sets(character):
    var worn_names = {}
    var raw_ids = {}
    var seen_item_ids = {}
    var gear = character.equipment.gear

    for slot in _OUTFIT_SLOT_ORDER:
        var item_id = gear.get(slot, null)
        if item_id == null or seen_item_ids.has(item_id):
            continue
        seen_item_ids[item_id] = true

        var item = ResourceScripts.game_res.items[item_id]
        var item_name = _normalize_analysis_tag(item.name)
        if slot in _WORN_EQUIPMENT_SLOTS and item_name != '':
            worn_names[item_name] = true

        var base_id = _normalize_analysis_tag(item.itembase)
        if base_id != '' and base_id != 'null':
            raw_ids[base_id] = true

        var code = _normalize_analysis_tag(item.code)
        if code != '' and code != 'null':
            raw_ids[code] = true

    return {
        'worn_names': worn_names,
        'raw_ids': raw_ids
    }

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
        if tag == '':
            continue
        if _looks_like_raw_metadata(tag):
            continue
        if _is_subject_or_body_tag(tag):
            continue
        if worn_names.has(tag):
            continue
        if raw_ids.has(tag):
            continue
        if seen.has(tag):
            continue

        seen[tag] = true
        cleaned.append(tag)

    return cleaned

func _sanitize_negative_analysis_tags(character, tags):
    var equipment_filters = _build_equipment_filter_sets(character)
    var raw_ids = equipment_filters.raw_ids
    var cleaned = []
    var seen = {}

    if not (tags is Array):
        return cleaned

    for raw_tag in tags:
        var tag = _normalize_analysis_tag(raw_tag)
        if tag == '':
            continue
        if _looks_like_raw_metadata(tag):
            continue
        if _is_subject_or_body_tag(tag):
            continue
        if raw_ids.has(tag):
            continue
        if seen.has(tag):
            continue

        seen[tag] = true
        cleaned.append(tag)

    return cleaned

func _sanitize_analysis_result(character, result):
    var raw_positive = result.get('positive_tags', [])
    var raw_negative = result.get('negative_tags', [])
    var cleaned_positive = _sanitize_positive_analysis_tags(character, raw_positive)
    var cleaned_negative = _sanitize_negative_analysis_tags(character, raw_negative)

    print('[PortraitGenerator][OutfitVision] Raw positive tags: %s' % str(raw_positive))
    print('[PortraitGenerator][OutfitVision] Cleaned positive tags: %s' % str(cleaned_positive))
    print('[PortraitGenerator][OutfitVision] Raw negative tags: %s' % str(raw_negative))
    print('[PortraitGenerator][OutfitVision] Cleaned negative tags: %s' % str(cleaned_negative))

    return {
        'positive_tags': cleaned_positive,
        'negative_tags': cleaned_negative,
        'confidence': result.get('confidence', 0.0)
    }

func _on_analysis_complete(result, from_cache):
    _set_buttons_disabled(false)

    var character = input_handler.interacted_character
    if character == null:
        _on_analysis_error('No active character was found')
        return

    var sanitized = _sanitize_analysis_result(character, result)
    var positive_tags = sanitized.positive_tags
    if positive_tags.empty():
        _on_analysis_error('The vision model returned no usable outfit tags. Press Reanalyze to try again')
        return

    var clothing_input = _get_clothing_input()
    if clothing_input == null:
        _on_analysis_error('Could not find the Clothing description input')
        return

    clothing_input.set_text(', '.join(positive_tags))
    _replace_vision_negative_tags(sanitized.negative_tags)

    if _panel != null and _panel.has_method('_generate_prompts'):
        _panel.call('_generate_prompts', true)

    var source_text = 'cached'
    if not from_cache:
        source_text = 'new'
    var confidence = int(round(float(sanitized.confidence) * 100.0))
    _set_status('Applied %s analysis (%d%% confidence): %d cleaned outfit tags' % [
        source_text,
        confidence,
        positive_tags.size()
    ])
    _save_settings()
