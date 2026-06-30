extends Node

var _ATTRIBUTE_OVERRIDES = {
    'leather_collar': {
        'description': 'leather slave collar'
    },
    'steel_collar': {
        'description': 'steel slave collar'
    },
    'elegant_choker': {
        'description': 'black choker with a silver heart in the center'
    },
    'amulet_of_recognition': {
        'description': 'gold necklace with a large green gem'
    },
    'animal_ears': {
        'description': 'fake animal ears headband'
    },
    'tail_plug': {
        'description': 'butt plug with an animal tail'
    },
    'animal_gloves': {
        'description': 'cosplay furry animal gloves'
    },
        # maybe make a animal randomizer for all the pieces so they match?
    'pet_suit': {
        'description': 'a slutty and revealing cat cosplay with matching tail ears and furry cat gloves'
    },
    'worker_outfit': {
        'description': 'slutty peaseants wear, covered chest, covered genitals'
    },
    'craftsman_suit': {
        'description': 'normal clothes with a leather work apron, craftsman, covered chest, covered genitals'
    },
    'seethrough_underwear': {
        'description': 'slutty lace lingerie, (nipples visible through lingerie, genitals visible through lingerie:1.3)'
    },
    # maybe something that checks if futa/male to add 'buldge' to this and remove penis/pussy/nipples from negative
    'service_suit': {
        'description': 'black leotard, long gloves, fishnet stockings, bunny tail, white bunny ear headband'
    },
    'handcuffs': {
        'description': 'leather wrist restraints'
    },
    'strapon': {
        'description': 'giant purple strapon'
    },
    'chastity_belt': {
        'description': 'chastity belt, <lora:chastity:0.6>'
    },
    # gonna add a few loras for those who will use the tag loader, if not they're pretty harmless here
    'stimulative_underwear': {
        'description': 'tentacle panties, (tentacle panties, living clothing:1.4),  <lora:tentacle_clothes:1>'
    },
    'tentacle_suit': {
        'description': 'tentacle outfit, (slutty tentacle suit, living clothing:1.4),  <lora:tentacle_clothes:1>'
    },
    'anal_beads': {
        'description': 'anal beads in ass, exposed anus, anal object insertion'
    },
    'anal_plug': {
        'description': 'anal plug in ass, exposed anus, anal object insertion'
    },
    'mask': {
        'description': 'white ceramic full face doll mask'
    },
    #stopped testing here
    'anastasia_bracelet': {
        'description': 'a large silver braclet with blue gems'
    },
    'anastasia_broken_bracelet': {
        'description': 'a large silver bracelet with red gems with a slight red glow'
    },
    'daisy_dress': {
        'description': 'an exquisite maid dress'
    },
    'daisy_dress_lewd': {
        'description': 'black lace crotchless panties, (black and white cloth revealing maid cosplay:1.3), frills, open front skirt, exposed shoulders, (exposed genitals, exposed breasts, exposed midriff:1.5),  breast support, (black sheer stockings and long gloves), NSFW'
    },
    'aire_bow': {
        'description': 'a powerfully enchanted elven bow'
    },
    'cali_collar': {
        'description': 'a leather slave collar with a tag that says cali'
    },
    'cali_exquisite_collar': {
        'description': 'a beautiful leather slave collar with a tag that says cali'
    },
    'cali_collar_enchanted': {
        'description': 'a purple glowing leather slave collar with a tag that says cali'
    },
    'cali_collar_enchanted_2': {
        'description': 'a red glowing leather slave collar with a tag that says cali'
    },
    'enslaving_collar': {
        'description': 'a leather and metal spiked collar'
    },
    'ramont_axe': {
        'description': 'a gigantic double sided battleaxe'
    },
    'erlen_sword': {
        'description': 'an elven sword'
    },
    'garb_of_forest': {
        'description': 'an enchanted armour made of leaves and bark'
    },
    'club': {
        'description': 'thick rough wooden club'
    }
}

# Crafted materials do not recolor the game's clothing sprites. These visual families
# describe the fixed sprite design instead of treating crafting parts as literal trim.
# Add aliases here as new item base IDs are discovered during testing.
var _VISUAL_FAMILY_ALIASES = {
    'robe': 'robe',
    'cloth_robe': 'robe',
    'clothrobe': 'robe',
    'pants': 'pants',
    'cloth_pants': 'pants',
    'clothpants': 'pants'
}

var _VISUAL_FAMILIES = {
    'robe': {
        'female': 'cropped charcoal-gray sleeveless fantasy tunic, deep plunging neckline, dark red short shoulder cape, shoulder guards, exposed cleavage, exposed midriff, covered nipples, blue hanging sash pouch at her right hip',
        'futa': 'cropped charcoal-gray sleeveless fantasy tunic, deep plunging neckline, dark red short shoulder cape, shoulder guards, exposed cleavage, exposed midriff, covered nipples, blue hanging sash pouch at her right hip',
        'male': 'charcoal-gray sleeveless fantasy tunic with a dark red short shoulder cape and shoulder guards',
        'default': 'charcoal-gray fantasy tunic with a dark red short shoulder cape'
    },
    'pants': {
        'female': 'short dark brown flared fantasy skirt with pale blue edging, bare thighs',
        'futa': 'short dark brown flared fantasy skirt with pale blue edging, bare thighs',
        'male': 'dark brown fitted cloth trousers with pale blue edging',
        'default': 'dark brown fantasy legwear with pale blue edging'
    }
}

# Secondary crafting parts that affect item construction or stats but are not visibly
# represented on clothing sprites. In particular, ArmorTrim must never become phrases
# such as "wooden trim" or "stone trim" in image prompts.
var _NON_VISUAL_CRAFTING_PARTS = {
    'ArmorTrim': true,
    'ArmorEnc': true,
    'ArmorCloth': true
}

var _PART_LABELS = {
    'WeaponHandle': 'handle',
    'ToolHandle': 'handle',
    'ToolBlade': 'blade',
    'ToolClothwork': 'cloth',
    'BowTrim': 'trim',
    'WeaponEnc': 'accent',
    'JewelryGem': 'gem'
}

var _reported_unmapped = {}

func item_description(item, sex = '', slot = ''):
    var attribute_desc = _attribute_override_description(item)
    if attribute_desc != '':
        return attribute_desc

    var visual_desc = _visual_family_description(item, sex)
    if visual_desc != '':
        return visual_desc

    return _generic_item_desc(item)

func has_visual_mapping(item):
    if _attribute_override_description(item) != '':
        return true
    return _visual_family_for_item(item) != ''

func report_unmapped(item, sex, slot):
    if has_visual_mapping(item):
        return

    var report_key = '%s|%s|%s' % [slot, str(item.code), str(item.itembase)]
    if _reported_unmapped.has(report_key):
        return
    _reported_unmapped[report_key] = true

    print('[PortraitGenerator][OutfitPrompt] Unmapped equipment: slot=%s sex=%s code=%s itembase=%s name=%s parts=%s' % [
        slot,
        sex,
        str(item.code),
        str(item.itembase),
        str(item.name),
        str(item.parts)
    ])

func _attribute_override_description(item):
    var override = _ATTRIBUTE_OVERRIDES.get(item.code, null)
    if override == null:
        override = _ATTRIBUTE_OVERRIDES.get(item.itembase, null)
    if override == null:
        return ''
    return override.get('description', '')

func _visual_family_description(item, sex):
    var family = _visual_family_for_item(item)
    if family == '':
        return ''

    var family_data = _VISUAL_FAMILIES.get(family, {})
    if family_data.has(sex):
        return family_data.get(sex, '')
    return family_data.get('default', '')

func _visual_family_for_item(item):
    var lookup_keys = [
        _normalize_key(str(item.code)),
        _normalize_key(str(item.itembase)),
        _normalize_key(str(item.name))
    ]

    for lookup_key in lookup_keys:
        if _VISUAL_FAMILY_ALIASES.has(lookup_key):
            return _VISUAL_FAMILY_ALIASES[lookup_key]
    return ''

func _normalize_key(value):
    return value.strip_edges().to_lower().replace(' ', '_').replace('-', '_')

func _generic_item_desc(item):
    var desc = item.name.to_lower()
    if item.parts.empty():
        return desc

    var primary_part = Items.itemlist[item.itembase].get('partmaterialname', '')
    var suffixes = []
    for part_key in item.parts:
        if part_key == primary_part:
            continue
        if _NON_VISUAL_CRAFTING_PARTS.has(part_key):
            continue
        if not _PART_LABELS.has(part_key):
            continue

        var mat_code = item.parts[part_key]
        if not Items.materiallist.has(mat_code):
            continue
        var mat = Items.materiallist[mat_code]
        if not mat.has('adjective') or mat.adjective == '':
            continue
        suffixes.append('%s %s' % [mat.adjective.to_lower(), _PART_LABELS[part_key]])

    if not suffixes.empty():
        desc += ' with ' + ' and '.join(suffixes)
    return desc
