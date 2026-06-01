extends Node

var races
var items
var _alpha_regex = null

var CLOTHED_TAGS = ['fully clothed']
var PORTRAIT_TAGS = ['portrait']

# Slot iteration order for equipment prompt generation.
# ass, crotch, underwear are at the end and conditionally skipped when legs are equipped.
var EQUIPMENT_SLOT_ORDER = ['chest', 'hands', 'head', 'neck', 'legs', 'rhand', 'lhand', 'underwear', 'ass', 'crotch']
var LEGS_BLOCKED_SLOTS = ['ass', 'crotch', 'underwear']

var NUDE_TAGS = {
    'male': ['nude'],
    'female': ['nude', 'nipples'],
    'futa': ['nude', 'futanari', 'nipples']
}
var SEX_NEGATIVE_TAGS = {
    'male': ['girl', 'woman', 'breasts'],
    'female': ['man', 'boy', 'beard', 'mustache', 'penis'],
    'futa': ['man', 'boy', 'beard', 'mustache']
}
var SEX_NUDITY_NEGATIVE_TAGS = {
    'male': ['nude', 'naked', 'penis'],
    'female': ['nude', 'naked', 'nipples'],
    'futa': ['nude', 'naked', 'penis', 'nipples']
}
var FUTA_TESTICLES_NEGATIVE_OPTION = 'testicles, scrotum, ballsack'

func _ready():
    races = modding_core.modules.PortraitGenerator_races
    items = modding_core.modules.PortraitGenerator_items

func build_prompts(character, positive_user_tags, clothing_user_tags, negative_user_tags):
    var sex = character.get_stat('sex')
    var race = character.get_stat('race')
    var age = character.get_stat('age')
    var skin_color = character.get_stat('body_color_skin')
    var skin_coverage = character.get_stat("skin_coverage")
    var eye_color = character.get_stat('eye_color')
    var eye_shape = character.get_stat('eye_shape')
    var hair_color = character.get_stat('hair_color')
    var hair_style = character.get_stat('hair_style')
    var hair_length = character.get_stat('hair_length')
    var beard = character.get_stat('beard')
    var facial_hair_color = character.get_stat('hair_facial_color')
    var height = character.get_stat('height')
    var breast_size = character.get_stat('tits_size')
    var ass_size = character.get_stat('ass_size')
    var penis_size = character.get_stat('penis_size')
    var wings = character.get_stat("wings")
    var wings_color = character.get_stat("body_color_wings")
    var tail = character.get_stat("tail")
    var tail_color = character.get_stat("body_color_tail")
    var horns = character.get_stat("horns")
    var horns_color = character.get_stat("body_color_horns")
    var ears = character.get_stat("ears")
    var penis_type = character.get_stat("penis_type")

    var nudity_tags = NUDE_TAGS.get(sex, [])
    var sex_negative_tags = SEX_NEGATIVE_TAGS.get(sex, [])
    var nudity_negative_tags = SEX_NUDITY_NEGATIVE_TAGS.get(sex, [])
    var race_descriptor = races.get_personal_descriptor(character, race)
    var body_tags = races.get_body_tags(race)
    var race_negative_tags = races.get_negative_tags(race)
    var skin_type = races.get_skin_type(race)

    var base_tags = subject_tags(sex, race_descriptor) + \
        age_tags(age, sex) + \
        body_tags + \
        hair_tags(hair_color, hair_length, hair_style, beard, facial_hair_color) + \
        skin_tags(skin_color, skin_type, skin_coverage) + \
        eye_tags(eye_color, eye_shape) + \
        body_type_tags(height, ass_size, sex) + \
        breasts_tags(breast_size, sex) + \
        wings_tags(wings, wings_color) + \
        tail_tags(tail, tail_color) + \
        horns_tags(horns, horns_color) + \
        ears_tags(ears)
    
    var face_tags = subject_tags(sex, race_descriptor) + \
        age_tags(age, sex) + \
        hair_tags(hair_color, hair_length, hair_style, beard, facial_hair_color) + \
        skin_tags(skin_color, skin_type, skin_coverage) + \
        eye_tags(eye_color, eye_shape) + \
        horns_tags(horns, horns_color) + \
        ears_tags(ears)
    
    var positive_tags = []
    if positive_user_tags:
        positive_tags.append(positive_user_tags)
    positive_tags += base_tags + CLOTHED_TAGS
    if clothing_user_tags:
        positive_tags.append(clothing_user_tags)
    var positive_prompt = ', '.join(positive_tags)

    var negative_tags = []
    if negative_user_tags:
        negative_tags.append(negative_user_tags)
    negative_tags += race_negative_tags + \
        sex_negative_tags + \
        nudity_negative_tags
    var negative_prompt = ', '.join(negative_tags)

    var nude_positive_tags = []
    if positive_user_tags:
        nude_positive_tags.append(positive_user_tags)
    nude_positive_tags += base_tags + \
        nudity_tags + \
        genitals_tags(penis_type, penis_size, skin_color)
    var nude_prompt = ', '.join(nude_positive_tags)

    var nude_negative_tags = []
    if negative_user_tags:
        nude_negative_tags.append(negative_user_tags)
    nude_negative_tags += race_negative_tags + \
        sex_negative_tags
    if sex == 'futa' and not futa_have_balls():
        nude_negative_tags.append(FUTA_TESTICLES_NEGATIVE_OPTION)
    var nude_negative_prompt = ', '.join(nude_negative_tags)
    var nude_positive_prompt = ', '.join(nude_positive_tags)
    
    var face_positive_tags = []
    if positive_user_tags:
        face_positive_tags.append(positive_user_tags)
    face_positive_tags += PORTRAIT_TAGS + face_tags
    var face_positive_prompt = ', '.join(face_positive_tags)

    var face_negative_tags = []
    if negative_user_tags:
        face_negative_tags.append(negative_user_tags)
    face_negative_tags += race_negative_tags + \
        sex_negative_tags
    var face_negative_prompt = ', '.join(face_negative_tags)
    
    return {
        'clothed_positive': positive_prompt,
        'clothed_negative': negative_prompt,
        'nude_positive': nude_prompt,
        'nude_negative': nude_negative_prompt,
        'face_positive': face_positive_prompt,
        'face_negative': face_negative_prompt
    }

func subject_tags(sex, race_descriptor):
    sex = {
        'male': 'boy',
        'female': 'girl',
        'futa': 'futa'
    }.get(sex, sex)
    var components = ['1%s' % sex]
    if race_descriptor:
        components.append(race_descriptor)
    return components

func age_tags(age, sex):
    sex = {
        'male': 'man',
        'female': 'woman',
        'futa': 'woman'
    }.get(sex, sex)
    return ['%s %s' % [age, sex]]

func skin_tags(skin_color, skin_type, skin_coverage):
    var skin = skin_color
    if skin_coverage:
        # Overwrite skin color with fur/scales color
        skin = skin_coverage_to_color(skin_color, skin_coverage)

    return ['(%s %s:1.2)' % [to_simple_color(skin), skin_type]]

func skin_coverage_to_color(skin_color, skin_coverage):
    var coverage_components = Array(skin_coverage.split("_"))
    if coverage_components.size() == 2:
        return coverage_components[1]
    elif coverage_components.size() > 2:
        return ' and '.join(coverage_components.slice(1, coverage_components.size() - 1))
    # The others (scales, kobold) don't actually affect skin color
    return to_simple_color(skin_color)

func eye_tags(eye_color, eye_shape):
    var components = ['%s eyes' % eye_color]
    if eye_shape != 'normal':
        components.append('%s pupils' % eye_shape)
    return components

func hair_tags(hair_color, hair_length, hair_style, beard, facial_hair_color):
    hair_color = {
        'yellow': 'blonde'
    }.get(hair_color, hair_color)
    var hair_prompt = ''
    if hair_length == 'bald':
        hair_prompt = 'bald'
    else:
        var hair_length_prompt = {
            'ear': 'very short',
            'neck': 'short',
            'shoulder': 'medium',
            'waist': 'long',
            'hips': 'extremely long'
        }.get(hair_length)
        match hair_style:
            'straight':
                hair_prompt = '(%s %s hair:1.2)' % [hair_length_prompt, hair_color]
            'pigtails', 'twinbraids':
                hair_prompt = '(%s %s hair:1.2) in %s' % [hair_length_prompt, hair_color, hair_style]
            'ponytail', 'bun', 'braid':
                hair_prompt = '(%s %s hair:1.2) in a %s' % [hair_length_prompt, hair_color, hair_style]
            _:
                hair_prompt = '(%s %s %s hair:1.2)' % [hair_length_prompt, hair_color, hair_style]
    var components = [hair_prompt]
    if beard != 'no':
        components += facial_hair_tags(beard, to_simple_color(facial_hair_color))

    return components

func facial_hair_tags(beard, facial_hair_color):
    return [ {
        'style1': 'short %s beard and bare lip' % facial_hair_color,
        'style2': 'medium %s beard and bare lip' % facial_hair_color,
        'style3': 'bushy %s beard and bare lip' % facial_hair_color,
        'style4': 'long %s beard and bare lip' % facial_hair_color,
        'style5': '%s braided mustache' % facial_hair_color,
        'style6': '%s horseshoe mustache' % facial_hair_color,
        'style7': 'thick %s braided mustache' % facial_hair_color,
        'style8': '%s handlebar mustache' % facial_hair_color,
        'style9': 'short %s braided beard' % facial_hair_color,
        'style10': 'long %s beard and mustache' % facial_hair_color,
        'style11': 'bushy %s braided beard' % facial_hair_color,
        'style12': 'long %s beard and handlebar mustache' % facial_hair_color
    }.get(beard, '')]

func body_type_tags(height, ass_size, sex):
    var build_tags = ['average build']
    if sex in ['female', 'futa']:
        build_tags = {
            'flat': ['slender', 'very narrow hips'],
            'small': ['slender', 'narrow hips'],
            'big': ['wide hips'],
            'huge': ['thick thighs', 'extremely wide hips']
        }.get(ass_size, ['average build'])

    var height_prompt = 'average height'
    if height in ['tall', 'towering']:
        height_prompt = 'very tall'
    elif height in ['short', 'petite', 'tiny']:
        height_prompt = 'very short'

    return [height_prompt] + build_tags

func breasts_tags(breast_size, sex):
    if breast_size == 'masculine':
        return ['defined abs']
    if sex == 'male':
        return []
    if breast_size == 'flat':
        return ['flat chest']
    breast_size = {
        'average': 'medium',
        'average_high': 'medium perky',
        'average_narrow': 'medium narrow',
        'average_wide': 'medium wide',
        'big': 'large',
        'big_high': 'large perky',
        'big_narrow': 'large narrow',
        'huge_high': 'huge perky',
        'huge_narrow': 'huge narrow',
        'huge_wide': 'huge wide'
    }.get(breast_size, breast_size)
    return ['%s breasts' % breast_size]

func wings_tags(wings, wings_color):
    wings = {
        'seraph': 'angel'
    }.get(wings, wings)
    if not wings:
        return []
    return ['%s %s wings' % [to_simple_color(wings_color), to_alpha(wings)]]

func tail_tags(tail, tail_color):
    tail = {
        'avali': 'bird'
    }.get(tail, tail)
    if not tail:
        return []
    return ['%s %s tail' % [to_simple_color(tail_color), to_alpha(tail)]]

func horns_tags(horns, horns_color):
    if not horns or horns == 'none':
        return []
    return ['%s %s horns' % [to_simple_color(horns_color), to_alpha(horns)]]

func ears_tags(ears):
    ears = {
        'avali': 'feathered',
        'bunny_drooping': 'floppy bunny',
        'bunny_standing': 'upright bunny',
        'demon': 'pointed',
        'elven': 'elf',
        'fish': 'fin',
        'orcish': 'pointed'
    }.get(ears, ears)
    if ears == 'normal':
        return []
    return ['%s ears' % ears]

func genitals_tags(penis_type, penis_size, skin_color):
    if penis_size:
        if penis_type == 'human':
            penis_type = ''
        return ['%s %s %s penis' % [penis_size, to_simple_color(skin_color), penis_type]]
    return ['vulva']

func to_simple_color(skin_color):
    var translated_color = {
        'human1': 'fair',
        'human2': 'light',
        'human3': 'light brown',
        'human4': 'brown',
        'human5': 'nut brown',
        'human6': 'dark brown',
        'human7': 'ebony',
        'dark1': 'dark grey',
        'dark2': 'very dark grey',
        'dark3': 'black',
        'dark_1': 'dark grey',
        'dark_2': 'very dark grey',
        'dark_3': 'black'
    }.get(skin_color, null)
    if translated_color:
        return translated_color

    return to_alpha(skin_color)
    
func to_alpha(value):
    if _alpha_regex == null:
        _alpha_regex = RegEx.new()
        _alpha_regex.compile('[\\d_]')
    return _alpha_regex.sub(value, '', true)

func build_equipment_prompt(character):
    var gear = character.equipment.gear
    var poss = 'his' if character.get_stat('sex') == 'male' else 'her'
    var has_legs = gear.legs != null
    var seen_item_ids = {}
    var phrases = []

    for slot in EQUIPMENT_SLOT_ORDER:
        var item_id = gear.get(slot, null)
        if item_id == null:
            continue
        if has_legs and slot in LEGS_BLOCKED_SLOTS:
            continue
        if seen_item_ids.has(item_id):
            continue
        seen_item_ids[item_id] = true

        var item = ResourceScripts.game_res.items[item_id]
        var desc = items.item_description(item)

        match slot:
            'head':
                phrases.append('wearing %s on %s head' % [desc, poss])
            'neck':
                phrases.append('wearing a %s around %s neck' % [desc, poss])
            'chest', 'legs', 'underwear', 'ass', 'crotch':
                phrases.append('wearing %s' % desc)
            'hands':
                phrases.append('wearing %s on %s hands' % [desc, poss])
            'rhand':
                phrases.append('holding a %s in %s right hand' % [desc, poss])
            'lhand':
                phrases.append('holding a %s in %s left hand' % [desc, poss])

    return ', '.join(phrases)

func futa_have_balls():
    return input_handler.globalsettings.futa_balls
