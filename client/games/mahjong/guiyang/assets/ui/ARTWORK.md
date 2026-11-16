# 贵阳麻将参考美术资源

制作方式：内置 image_gen；参考用户图 `codex-clipboard-af972072-beb8-4f7f-bd62-85030f48de30.png`。原图未修改。

全部资源保存在 `client/games/mahjong/guiyang/assets/ui/`。背景仅作环境装饰，头像为四格图集，木纹用于原有三维桌框；游戏桌、牌墙、手牌、弃牌和副露均由真实三维模型渲染。

## 最终提示

### mahjong_garden.png

Use case: precise-object-edit. Asset type: landscape game environment background. Use the attached Guiyang mahjong interface as composition and visual style reference. Create a clean panoramic 16:9 premium realistic illustrated Chinese leisure-room veranda facing Guiyang lake, Jiaxiu Tower pavilion, distant city skyline, mountains, bright fresh blue sky. Preserve warm wooden room framing, potted flowering greenery, side chairs with sleeping ginger cats at far left, small side tea cup and cushions; a cheerful relaxed afternoon. REMOVE completely the foreground mahjong table, all tiles, player portraits, buttons, HUD, typography, calligraphy, signage, score badges, decorations with text and UI. Replace removed table with a continuous natural dark timber floor/terrace so the center and lower two-thirds remain unobstructed for a separately rendered REAL 3D mahjong table. Scenery behind the table starts in upper third. Natural soft light, warm wood with lush green plants, elegant high-quality game art. No central props, no fake table, no writing, no logos, no watermark.

### mahjong_portraits.png

Use case: identity-preserve. Asset type: four-person portrait atlas for Guiyang mahjong game HUD. Reference the friendly realistic 3D illustrated people in the supplied interface. Create a 2x2 atlas with FOUR EQUAL square cells, each cell containing a centered head-and-shoulders avatar against a soft light sage background, no frame. Top-left: friendly adult woman long dark hair in light elegant blouse (local player). Top-right: friendly middle-aged man with glasses short dark hair ivory shirt (right opponent). Bottom-left: cheerful young adult man short black hair light casual shirt (top opponent). Bottom-right: smiling adult woman dark tied hair cream shirt (left opponent). Matched scale and clear shoulder-up crop, whole hair and head, premium approachable Chinese game character art with refined natural faces, realistic detail, warm daylight. Grid exact, no overlap between cells. Do not include table, tiles, cards, hands, scenery, names, scores, text, UI, signs, watermarks or badges.

### mahjong_wood.png

Use case: precise-object-edit. Asset type: seamless square PBR base-color wood material for actual 3D mahjong table frame. Extract the warm polished brown timber mood of the table border in the supplied image into a flat orthographic TOP-DOWN material texture. Uniform medium warm honey-walnut brown wood, subtle fine straight organic wood grain, low contrast, realistic refined natural wood, diffuse albedo only. Seamless tileable square. No tabletop outline, no perspective, no joints, no objects, no words, no shadows, no highlight spots, no vignette, no baked lighting, no strong yellow stripes. The game renderer provides lighting.

## 黑金翡翠会所视觉资源（2026-10-09）

制作方式：内置 `image_gen`，未使用 CLI/API 回退。用户参考图为 `C:/Users/Administrator/AppData/Local/Temp/codex-clipboard-f9f8c07b-4aab-4fa0-aaea-dcaf1e9cf74a.png`（1672 × 941）。原图未修改。本次仅添加位图资源与本说明，三维麻将牌、模型、交互逻辑由项目独立维护。

### 选定资源与复核

- `mahjong_club_room.png`：1672 × 941，RGB。生成来源 `C:/Users/Administrator/.codex/generated_images/01a12053-ffee-7260-8c24-6a7682bffff6/exec-49e020e4-7999-4a23-9935-a8b1caa9eb86.png`。以用户参考图为环境与风格输入；已检查中央空场、两侧翡翠灯带、黑色漆面与克制金色反光；无牌桌、牌、人物、文字或 UI。
- `mahjong_club_actions.png`：2172 × 724，RGBA。生成来源 `C:/Users/Administrator/.codex/generated_images/01a12053-ffee-7260-8c24-6a7682bffff6/exec-59fe9fa3-93a8-4a15-a620-af8b16b84ac3.png`。由参考设计描述重新生成，完整保留 吃、碰、杠、胡、过 五个动作字与翡翠、金、青蓝、绯红、石墨配色。真实透明通道占画布约 86.29%；未对生成位图做裁切、缩放、阈值清理或其他程序化编辑。

内置生成器未采用最初请求的 5:1 画布，最终使用 3:1 画布与五个等大的正方形图集区域。推荐 `Rect2(92 + 422 * index, 210, 300, 300)`，`index = 0..4`。边界坐标以左上角为原点，右/下为排除端点。字序对应 吃、碰、杠、胡、过。

| 动作 | 等大图集区域 x/y/w/h | 区域内全部非零 alpha 边界 l/t/r/b | 区域内 alpha > 16 可见轮廓边界 l/t/r/b |
| --- | --- | --- | --- |
| 吃 | 92 / 210 / 300 / 300 | 38 / 32 / 262 / 261 | 43 / 42 / 258 / 257 |
| 碰 | 514 / 210 / 300 / 300 | 34 / 10 / 260 / 260 | 43 / 42 / 258 / 257 |
| 杠 | 936 / 210 / 300 / 300 | 4 / 31 / 266 / 300 | 43 / 42 / 257 / 257 |
| 胡 | 1358 / 210 / 300 / 300 | 25 / 32 / 269 / 260 | 32 / 42 / 265 / 257 |
| 过 | 1780 / 210 / 300 / 300 | 37 / 34 / 263 / 260 | 42 / 42 / 258 / 257 |

可见完整轮廓与光晕均包含在以上区域，最小可见留边为 32 像素。生成 alpha 中仍有少量 alpha ≤ 16 的极淡散点，全部非零 alpha 边界因此大于可见轮廓；保留原生生成 alpha，不宣称逐像素完全无散点。

### mahjong_club_room.png 精确提示词

```text
Use case: precise-object-edit.
Asset type: 16:9 landscape game environment backdrop for a real 3D Guiyang mahjong game.
Input image: user-provided Chinese mahjong club interface, a style and environment reference only.
Primary request: derive the empty club room environment from this reference, removing every foreground and UI element. A refined luxurious Chinese mahjong club interior, dark black lacquer architecture, graphite surfaces, understated thin warm gold specular trim, with vivid emerald vertical architectural accent lights at the far left and far right only.
Composition/framing: panoramic 16:9 landscape, level camera. Broad extremely dark uncluttered empty central region and lower two-thirds reserved for a live 3D mahjong table rendered separately. Architecture and illumination mostly around the outer edges and upper third. Dark floor with very soft subtle reflections. No bright visual focal point in the central table region.
Lighting/mood: atmospheric premium night club, restrained emerald edge lights and sparse small warm gold architectural glints, deep black atmosphere, controlled highlights, avoid harsh oversaturated bloom.
Materials/textures: refined black lacquer, brushed graphite, restrained gold details, clean surfaces. Subtle realistic upscale game environment art matching the reference.
Constraints: no mahjong table, no tiles, no card objects, no furniture or props in the center, no people, no portraits, no circular buttons, no HUD, no Chinese letters, no English text, no logos, no signage, no watermark. Remove the reference table completely and replace it with empty continuous dark floor. Do not invent busy decor, gold dragons, statues, chandeliers, bright windows or vegetation. Image must fill an exact 16:9 canvas.
```

### mahjong_club_actions.png 选定版精确提示词

```text
Use case: stylized-concept.
Asset type: transparent game spritesheet, five SMALL mahjong action icons with large empty transparent gutters.
Create a fresh transparent spritesheet of exactly five isolated circular icons in one horizontal row. Wide 3:1 canvas. The icons must be SMALL on the canvas, with matching circle diameters of only 11 percent of the entire canvas width (each icon is roughly HALF the width of its invisible 20-percent-wide cell). Every icon center sits on the horizontal middle line, at x=10%,30%,50%,70%,90%. The circle artworks occupy only the central third of the canvas height. Leave expansive empty transparent space above and below. Leave completely transparent gaps between circles that are about as wide as the circle radius. Leave generous outer transparent margins at left and right. No square frames or guides.
The five exact Chinese characters from left to right are "吃" "碰" "杠" "胡" "过". One character on each icon. Bold original calligraphic brush lettering, clear and readable, glossy dark faceted jewel disks, polished thin metal rims, luxury Chinese mahjong club interface art.
Icon 1 emerald green and dark emerald, pale warm gold 吃, thin gold metallic outer rim, emerald inner rim.
Icon 2 dark amber and gold, pale gold 碰, gold rims.
Icon 3 dark cyan-blue jewel, pale cyan 杠, blue inner rim and thin gold rim. 杠 is 木 plus 工.
Icon 4 crimson dark red jewel, pale warm gold 胡, thin gold rim, compact flame accents hugging just its rim. 胡 is 古 plus 月.
Icon 5 graphite charcoal jewel, bright white-silver 过, muted silver rims.
Restrained illumination: very small narrow rim glows ONLY. All glow must stay within 12 percent of total canvas width for each icon. No broad halo clouds, no far-reaching particle speckles, no overlap between icons. Every pixel in the large empty gutters and margins must have exactly zero alpha.
Real transparent background. No checkerboard, black fill, white fill, mockup background, table, tiles, people, portraits, HUD, scene, English, labels or watermark.
The most essential requirement is that these are SMALL isolated icon sprites surrounded by LOTS OF TRANSPARENT EMPTY SPACE, suitable for equal square atlas regions. Do not make the circles large enough to touch or fill the canvas height.
```

### 未选用的动作图集迭代与精确提示词

第一版以用户参考图为输入，产物 `exec-bc298cd7-3695-4b1c-a443-5af30fac3a2f.png`（1983 × 793 RGBA）仍有过宽光晕；第二版以第一版为编辑输入，产物 `exec-614f0cff-67ee-4a0c-a93d-6505a72e999d.png`仍未充分增加间距。均未作为项目资源引用。

第一版：
```text
Use case: background-extraction.
Asset type: transparent horizontal five-button spritesheet for a Chinese mahjong game.
Input image: the user-provided mahjong UI reference. The FIVE circular action buttons in its bottom-right are the edit targets, in the original order 吃 碰 杠 胡 过.
Primary request: extract and carefully refine those five original action button designs into a clean production spritesheet. Retain their original Chinese lettering and visual style: thick highly legible elegant bold brush characters, glossy dark faceted circular jewels, subtle polished metallic edges, premium game UI.
Composition/framing: exact wide 5:1 canvas, 2560 pixels wide by 512 pixels high. ONE ROW OF FIVE EQUAL SQUARE CELLS, each 512 by 512. Cell centers at x=256,768,1280,1792,2304 and y=256. Every circle has the same 320-pixel core diameter, centered in its own cell. Entire silhouette and every glow must fit inside a 400-pixel square within each cell, leaving at least 56 pixels completely transparent safety padding on all cell edges. No visible cell borders or separators. No cross-cell light or particles. All five centers and diameters precisely aligned.
Cell 1 text verbatim: "吃"; emerald green jewel, pale warm gold lettering, warm gold outer edge with vivid thin emerald inner rim and controlled green glow.
Cell 2 text verbatim: "碰"; dark amber-gold jewel, pale gold lettering, polished gold edge, controlled warm gold glow.
Cell 3 text verbatim: "杠"; vivid cyan-blue jewel, pale cyan lettering, polished gold edge and bright blue inner rim, controlled cyan glow. The character must be 杠, with 木 at left and 工 at right.
Cell 4 text verbatim: "胡"; crimson red jewel, pale warm gold lettering, polished gold edge, controlled thin flame/ember halo around the circular core. Entire halo contained within this cell with ample transparent padding. The character must be 胡, with 古 at left and 月 at right.
Cell 5 text verbatim: "过"; charcoal graphite jewel, white-silver lettering, polished muted silver outer edge, minimal soft cool glow.
Background: real transparent alpha, not black, not checkerboard, not opaque white. Preserve genuine alpha around each circle, shadow and glow.
Constraints: use exactly the five text characters 吃 碰 杠 胡 过, one character per button, no extra text, no English, no subtitles, no fake typographic glyphs. No portraits, table, tiles, room, interface panels, arrows, pointer, watermark. Correct isolated circular buttons only. Avoid excessive particles or long fire trails. Contrast must remain readable at small on-screen button sizes.
```

第二版：
```text
Use case: precise-object-edit.
Asset type: transparent five-button mahjong spritesheet.
Input image: the attached five-button image is the edit target.
Change only spatial layout and halo strength. Preserve the existing five circle artworks, their precise Chinese characters 吃 碰 杠 胡 过, their emerald/gold/cyan-blue/crimson/graphite colors, faceted glossy jewels, metallic edges, brush lettering and left-to-right order.
Keep the same wide 1983 by 793 pixel canvas. The sheet contains five INVISIBLE EQUAL SQUARE ATLAS REGIONS along its middle horizontal row. Each square is 396 pixels wide and 396 pixels high. Place their centers at x=198,595,992,1388,1785 and y=396.
Reduce every circle to a matching 230-pixel diameter core. Restrict each full silhouette and all glow/embers/shadow to a maximum 280-pixel diameter centered on the circle. This leaves over 58 pixels empty transparent padding within every square region, and a wide clear transparent gutter between adjacent buttons. The crimson Hu flame halo must stay compact and fully contained within the 280-pixel limit.
Remove the large fuzzy halo clouds and all far-reaching translucent noise. Use only a very narrow soft rim glow. All canvas pixels outside the five 280-pixel disks must have exactly zero alpha. Top and bottom parts of the canvas and outer left/right margins must be completely transparent. Real transparent background, no black background, no checkerboard. Render no square guides.
Invariants: same artwork and text, five separate isolated circles on one horizontal baseline, precisely matching core diameters, no perspective, no table/tiles/portrait/UI, no added text, no watermark. This is a production game atlas: generous transparent space around all five entire button outlines is essential.
```

### 透明标识与三维桌布补充（2026-10-09）

- `mahjong_club_logo.png`：1672 × 941，RGBA。内置 `image_gen` 编辑用户参考图，提取独立标识；生成来源 `C:/Users/Administrator/.codex/generated_images/01a12053-ffee-7260-8c24-6a7682bffff6/exec-810dd775-22a0-48bc-8531-835496269632.png`。可见文字为 小板凳、贵阳麻将、棋牌、GUIYANG MAHJONG、本地玩法·纯正贵阳。背景为真实 alpha，无黑色面板；完全透明像素占约 54.56%。全部非零 alpha 边界 `[35,29,1640,915]`；alpha >16 的可见边界 `[137,52,1611,892]`（可选 AtlasTexture 区域 `Rect2(137,52,1474,840)`）。已目视复核完整题字、印章、英文副题与本地玩法标语。
- `mahjong_club_felt.png`：1254 × 1254，RGB。内置 `image_gen` 新建的正交俯视深翡翠织物漫反射色图，牡丹/云纹提花与细织纹；生成来源 `C:/Users/Administrator/.codex/generated_images/01a12053-ffee-7260-8c24-6a7682bffff6/exec-2f5e9e8e-b589-43d5-8f01-5aeb1e48289a.png`。无文字、牌、桌框、界面、透视、烘焙高光/阴影或暗角。真实三维桌面使用单张完整 UV 覆盖并禁用重复，保留第一版较克制的提花与织物细节。生成提示包含无缝重复要求，但两对边缘不是逐像素相等：0..255 RGB 平均绝对差为左/右 14.15、上/下 13.13，因此不宣称经严格无缝验收。

以上两张最终资源直接复制原生生成文件，SHA256 与来源文件一致，未做程序化位图编辑。

#### mahjong_club_logo.png 精确提示词

```text
Use case: background-extraction.
Asset type: transparent Chinese mahjong game logo cutout.
Input image: the attached user-provided mahjong club interface is the edit target.
Primary request: extract ONLY the complete gold logo artwork from the upper-left corner of the reference interface into a standalone transparent logo. Preserve its original arrangement, original expressive brush calligraphy, text, gold material, tiny dark-emerald decorative brush accent, fine line accents and red seal. Remove all surrounding room, black background, table and interface.
The logo consists of smaller gold "小板凳" at the top, very large gold "贵阳麻将" in the middle, the small vertical red "棋牌" seal at its right, small uppercase "GUIYANG MAHJONG" below, a fine gold separator line, and the bottom gold tagline "本地玩法·纯正贵阳". These exact text strings must be preserved. Preserve the original logo's lettering shape and composition from the reference, not redesign it.
Composition: centered standalone complete logo with a snug landscape crop, covering most of the width and height while retaining a modest transparent safety margin around all strokes and any restrained glow. Preserve complete bottom tagline, complete English subtitle and complete top calligraphy.
Background: genuine transparent alpha. NO black rectangle, NO dark panel, NO filled backdrop, NO room remnants, NO checkerboard. The transparency must show through every empty area around the calligraphy and between letters. Only the original logo artwork and text remain.
Constraints: no additional writing, no added emblems, no portraits, HUD, circular buttons, table, tiles or watermark. Gold brush lettering must retain clear contrast on a dark room backdrop. No expanded noisy glow.
```

#### mahjong_club_felt.png 选定版精确提示词

```text
Use case: stylized-concept.
Asset type: square seamless PBR base-color fabric texture for a real 3D Guiyang mahjong tabletop.
Primary request: a deep emerald premium fine woven felt textile with a subtle embossed Chinese peony and flowing cloud-contour jacquard pattern inspired by upscale Chinese mahjong cloth.
Composition: square flat orthographic top-down textile swatch, image entirely filled with continuous fabric, no perspective. Truly seamless tileable pattern along all four edges. Pattern repeats continuously with matching left/right and top/bottom boundaries. Use gently flowing organic Chinese peony outlines and cloud contours, restrained small-to-medium repeat scale, refined fine woven fiber detail.
Color palette: deep dark emerald green ground with restrained low contrast turquoise-emerald contour linework, premium elegant Chinese club mood. The pattern must be discernible but subtle and must remain darker than mahjong tiles placed on it.
Materials/textures: fine soft dense fabric weave and understated embossed/jacquard pattern, even diffuse color only. The game renderer supplies all lighting and shading. No baked lighting, no directional shadows, no specular highlights or bright spots.
Constraints: diffuse albedo/base-color map only, square seamless texture; no words, no Chinese characters, no English lettering, no logos, no graphic stamp, no table outline or rim, no board divisions, no tiles, no UI, no buttons, no perspective, no border, no vignette, no central focal motif or watermark. Do not render a finished mahjong table.
```

#### 桌布边缘修复尝试（未选用）

一次内置编辑以 `mahjong_club_felt.png` 为输入，产物为 `C:/Users/Administrator/.codex/generated_images/01a12053-ffee-7260-8c24-6a7682bffff6/exec-1417946a-73cc-4079-81cd-759a1e13c333.png`（1254 × 1254 RGB）。边缘差降为左/右 11.98、上/下 11.80；仍非严格像素匹配。最终桌面采用单幅完整覆盖，不需要重复边缘，故选用第一版较柔和织纹，不继续生成。

```text
Use case: precise-object-edit.
Asset type: square seamless repeatable fabric PBR diffuse texture.
Edit target: the attached dark emerald woven peony-and-cloud jacquard textile.
Change only edge continuity to make this image a truly seamless repeating texture. Keep the same square canvas, deep emerald palette, low-contrast turquoise-emerald contour pattern, fine woven fibers, pattern scale and premium fabric appearance.
The current left/right and top/bottom boundaries do not connect exactly. Repair the perimeter so that peony petals, leaves and cloud lines ending at the left edge continue from the SAME vertical location and shape at the right edge; those ending at the top continue at the SAME horizontal location and shape from the bottom. Left and right pixel color/fiber values must match, and top and bottom pixel color/fiber values must match. Imagine a continuous infinitely repeated cloth, with this image only one periodic tile. Retain visual texture all the way to the edges; do not hide seams with a border or a blank strip.
No perspective, no lights, no highlights, no shadows, no text or lettering, no table, tiles, UI or objects. Diffuse basecolor only. Preserve the existing central peony and cloud appearance while naturally continuing its pattern across matching opposite edges.
```
