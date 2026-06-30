# Local AI Outfit Analysis

PortraitGenerator can capture the character currently displayed in the character panel, combine the image with the character's equipped-item metadata, and ask a local Ollama vision model to produce clothing tags.

## Requirements

- Ollama 0.12.7 or newer.
- A local vision model. The default is `qwen3-vl:4b`.

Install the default model from a terminal:

```text
ollama pull qwen3-vl:4b
```

Ollama normally serves its API at:

```text
http://127.0.0.1:11434
```

## Using it

1. Open a character's information panel.
2. Open PortraitGenerator.
3. Confirm the Ollama URL and model under **AI outfit analysis**.
4. Press **Analyze portrait + equipment**.
5. The mod temporarily hides its prompt window, captures the displayed character region, and reopens the window.
6. The returned visual tags replace the Clothing description field. Suggested negative tags are merged into the Negative prompt field.
7. Full prompts are regenerated automatically.

Use **Reanalyze** to ignore the cache and inspect the current image again.

## How it works

The image model receives:

- A cropped screenshot of the character display.
- Occupied equipment slots.
- Item names and base IDs.
- Crafted part metadata as identification hints.
- Instructions explaining that clothing crafting materials do not recolor the game's outfit sprites.

The model is instructed to describe only visible garments, armor, accessories, footwear, and held equipment. Character appearance, pose, background, and interface elements should be omitted.

## Cache

Results are cached by vision model, character sex, and equipped-item combination at:

```text
user://portrait_generator_outfit_cache.json
```

Changing the equipment creates a different cache entry. Pressing **Reanalyze** bypasses the existing entry.

## Troubleshooting

### Could not contact Ollama

Start Ollama and verify the URL. On the same computer, the default should be `http://127.0.0.1:11434`.

### Model not found

Run:

```text
ollama pull qwen3-vl:4b
```

Or enter the name of another installed Ollama vision model.

### The captured image is wrong

The analyzer captures the character area currently displayed by the game. Close other windows that overlap the character panel, then press **Reanalyze**.

### VRAM usage

The request uses `keep_alive: 0`, so Ollama unloads the vision model after the analysis completes. This reduces conflicts with ComfyUI, though the initial model load may take longer.
