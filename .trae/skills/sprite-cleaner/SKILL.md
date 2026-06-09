---
name: "sprite-cleaner"
description: "Cleans up sprite sheets by automatically removing grid lines and pure color backgrounds (e.g. green screen). Invoke when user wants to clean, make transparent, or remove background from a sprite image."
---

# Sprite Cleaner Skill

This skill utilizes the custom Python script located at `c:/projects/g1/tools/sprite_cleaner.py` to automatically process and clean up sprite sheet images.

## Capabilities:
1. **Grid Line Removal**: Clears grid lines specifically by providing the grid column/row counts. This completely avoids the previous "guesswork" that failed due to anti-aliasing.
2. **Background Removal**: Targets standard green screens (Hue 30-90) directly and uses a flood fill from the borders to wipe it out.
3. **Despill**: Automatically removes green fringing (anti-aliasing artifacts) from the edges of the sprites.
4. **Color Correction**: Completely clears the RGB values of transparent pixels to prevent ghost colors (like cyan/black edges) when rendered in Godot.

## Usage Instructions:

When the user asks you to clean up a sprite or remove its background, follow these steps:

1. **Locate the target image**: Confirm the absolute path of the input image.
2. **Determine the output path**: Usually, overwrite the original file or save it with a `_clean.png` suffix depending on the user's request.
3. **Identify Grid Layout**: Determine if the image is a sprite sheet and how many columns (`grid_w`) and rows (`grid_h`) it has.
4. **Execute the tool**: Use the `RunCommand` tool to execute the python script.

### Example Command:
```bash
python c:/projects/g1/tools/sprite_cleaner.py "c:/projects/g1/素材/input.png" "c:/projects/g1/素材/output.png"
```

### Optional Arguments:
- `--tolerance <int>`: Adjusts the background color tolerance (0-255, default is 30). If the background is noisy and not fully removed, run the command again with a higher tolerance.

## Important Notes:
- ALWAYS use absolute paths for the input and output arguments to avoid working directory issues.
- Do NOT try to write new OpenCV scripts for background removal manually. ALWAYS use this established tool first.
