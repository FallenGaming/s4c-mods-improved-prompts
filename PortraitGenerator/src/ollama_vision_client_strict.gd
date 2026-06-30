extends "ollama_vision_client.gd"

# Tightens the VLM request so the returned positive tags describe the outfit only.
# The UI still sanitizes the result because local vision models can ignore instructions.

func _build_analysis_prompt(equipment_context, schema):
    return """Analyze this cropped 2D fantasy-game character image so its visible outfit can be recreated by an image-generation model.

Known equipped items:
%s

Rules:
1. Describe only visible clothing, armor, accessories, footwear, and held equipment.
2. Treat the equipped-item list only as identification hints. Determine garment silhouette, coverage, colors, trim, layers, and visible accessories from the image.
3. Crafting materials do not recolor clothing in this game. Never copy crafting fields into the output and never turn ArmorTrim, ArmorBase, or similar metadata into literal garment materials. A material may describe a clearly visible held weapon or tool.
4. Do not describe the character's face, hair, eyes, skin, age, sex, race, height, body shape, breasts, hips, pose, expression, background, camera framing, user interface, or art style.
5. Do not output subject or framing tags such as 1girl, woman, female, solo, cowboy shot, portrait, upper body, or full body.
6. Do not output raw item IDs, slot names, key=value fields, base IDs, codes, or crafting metadata such as ArmorTrim=wood.
7. For worn garments, prefer specific visual tags such as cropped robe, short skirt, deep neckline, red trim, exposed midriff, bare shoulders, or bare thighs instead of merely repeating an equipped item name.
8. For held items, a concise visual tag such as wooden club is allowed.
9. Use short comma-ready Stable Diffusion tags, not sentences and not prose.
10. Put only likely clothing or equipment misreadings in negative_tags, such as long robe, floor-length dress, trousers, long sleeves, gloves, boots, or headwear.
11. Do not invent items for empty equipment slots. Omit uncertain details rather than guessing.
12. Return only JSON matching this schema:
%s
""" % [equipment_context, JSON.print(schema)]
