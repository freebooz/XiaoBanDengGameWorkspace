# Landlord login bitmap assets

Generated with built-in image_gen on 2026-10-09. No manual pixel edits, crops, compositing or resizing were performed. Only raw selected PNGs were copied into the project.

## Provenance and selected files

Original source: C:/Users/Administrator/AppData/Local/Temp/codex-clipboard-9b2661aa-74b8-405d-b005-012622d4ef7e.png, copied unchanged to login_reference.png (941 × 1672).

login_village_background.png: 941 × 1672. Raw generated source: C:/Users/Administrator/.codex/generated_images/01a1210b-2abf-7780-8666-d99966d04f01/exec-d3038ebf-2962-4182-b5dc-b46865e5e11e.png.

login_control_atlas.png: 1586 × 992, RGBA. Raw generated source: C:/Users/Administrator/.codex/generated_images/01a1210b-2abf-7780-8666-d99966d04f01/exec-b9311157-7a1b-4a15-a20e-55b8556c96c0.png.

## Native AtlasTexture regions

SHA256 of copied selected files:

- login_reference.png: 4A6C72587C9623E21A48D5E3DF3F1FB30CA76721095533E4C3713E255DD67002
- login_village_background.png: DE062FBE6665292B32AC821968C1E4958041BFA9934EA2CF66E7471415E926D1
- login_control_atlas.png: 4DA9E7C8E6B76B13A582F0D93CF6B0F76A0A4456EE169B55DB0B9FB166FE4E9E

login_atlas.json contains equal-sized regions, [x, y, width, height]:

- input: [94, 190, 1400, 240]
- button: [94, 562, 1400, 240]

Use as native texture regions; source PNG remains intact. Both textures are blank and have no baked text or icons. At 5.83:1 these regions are close to the requested ~5.5:1.

## Visual and alpha audit

Viewed original and generated files independently. Background retains the top brand sign, tree, lantern, stool/cards/hat, lower four-person card-playing family, dog/chickens, houses and twilight palette. The central form is removed and reconstructed as blue mountains and distant village. This is generated inpainting and is visually close; exact pixel preservation outside the form is not claimed.

Atlas is Format32bppArgb, actual alpha transparency. First raw audit found 887348 alpha0 pixels, 685951 partially transparent pixels, and 13 alpha255 pixels. Samples (0,0), (700,480) have alpha0; input center (700,300) and wood center (700,650) have alpha253. No baked black background; the viewer renders transparency as black. Main body bounds above alpha16: input [95,191,1397,235], button [94,568,1399,228]. Main body bounds above alpha128: input [95,192,1396,233], button [95,569,1397,225]. The selected regions exclude the distant stray flecks, but thin low-alpha colored edge fringe remains in the raw generated atlas. This is a recorded generator limitation, not a fully clean mask claim.

One targeted transparency repair was generated at C:/Users/Administrator/.codex/generated_images/01a1210b-2abf-7780-8666-d99966d04f01/exec-b2f7b292-6070-4b0d-b66f-f2cfd5cf8e26.png. It increased visible fringe, so it was rejected. No further generation.

## Exact prompts

### Background

Use case: precise-object-edit
Asset type: portrait background bitmap for native Godot login UI.
Input image 1: edit target. Keep exact 941x1672 aspect ratio and the scene framing.
Primary request: Remove ONLY the central login UI from x205 through735 y510 through987: both cream phone/password input boxes, their icons/text, large golden login button, forgot password and register links/divider, WeChat and guest login buttons. Inpaint their footprints with continuous unobtrusive blue distant mountain/village landscape coherent with surrounding scenery. The empty middle will receive native UI controls later.
Invariants: Preserve the original image's top wooden golden Chinese 小板凳 斗地主 brand sign, stool, playing cards, straw hat, hanging lantern, huge ancient tree; preserve all original lower family members playing cards, table, wooden stools, dog, chickens, village houses, their architecture and twilight warm lantern / blue landscape palette. Preserve all existing decorative scene text outside the central removed UI. Keep every part outside the central login form as closely unchanged as possible.
Avoid: any new UI, any input frame, button, central text or icons. No new people or objects. No crop, no redesigned logo, no cartoon style shift.

### Atlas

Use case: stylized-concept
Asset type: real transparent PNG atlas of two native game UI sprites.
Input image 1: visual style reference ONLY. Match its central cream rounded input fields and honey golden beveled wood buttons.
Generate a 1024x640 transparent canvas, alpha zero outside the sprites. Exactly TWO blank horizontal rounded rectangles, both equally sized approximately 880x160, width:height 5.5:1. Arrange one at x72,y100 and the other at x72,y380, with generous fully transparent margins and gap. FIRST row: blank warm cream paper/plastic input field, slightly raised rounded bevel, tan edge trim, fine understated cream texture, matching original form. SECOND row: blank honey golden wood button, rounded cut/beveled corners, highlighted upper edge and richer golden lower bevel, visible subtle horizontal natural woodgrain like original login button.
No text of any kind, no phone or lock icon, no WeChat or guest icons, no logos, no scenery, no extra sprite. Front-on orthographic flat UI surfaces. Preserve premium warm PBR texture of reference. No perspective tilt. No cast shadows outside sprites. IMPORTANT: true RGBA transparency, never bake checkerboard, never bake a black backdrop. Only the two solid sprites have nonzero alpha.

### Rejected targeted repair

Use case: background-extraction
Input image 1: edit target sprite atlas. Repair ONLY transparency masking. Preserve the exact cream top input sprite and golden horizontal woodgrain lower button silhouette, texture, sizes and locations. Make each sprite fully opaque alpha255 in its solid interior and proper antialiased boundary. Everything outside the exact TWO clean sprite silhouettes must be fully transparent alpha0: remove all stray colored flecks, white/yellow/red fringe debris, glow, shadow and semi-transparent noise in surrounding margins and between rows. Background must be real transparency, never black pixels or checkerboard pixels. No changes to sprite artwork, no text or icons. Keep same 1586x992 dimensions, two clean isolated blank sprites. Preserve generous transparent outer margins and row gap.
