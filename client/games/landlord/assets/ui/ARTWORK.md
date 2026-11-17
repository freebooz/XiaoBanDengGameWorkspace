# 斗地主参考设计资产

制作方式：内置 `image_gen` 工具。参考：用户提供的园林木桌斗地主设计图 `codex-clipboard-62d5b7cf-0461-4aab-9b0f-fd63de47d672.png`。原参考未修改；生成结果复制到当前项目。

## 最终提示记录

### landlord_garden.png

Playable landscape Chinese card-game background, 16:9. Preserve Chinese lakeside pavilions, distant blue mountains, golden autumn foliage, warm veranda railings and afternoon light. Remove all interface, text, logos, buttons, cards, avatars, people and the foreground round table. Replace the table with continuous dark timber veranda floor; keep peripheral tea set and foliage. Broad central/lower space stays clear for a real 3D table, cards and UI. Premium semi-realistic game environment. No humans, animals, lettering, watermark or UI.

### landlord_opponents.png

Transparent two-player portrait sprite atlas, 2:1 with two equal square cells. Adult male in the left cell, adult female in the right. Preserve reference identities, ornate ivory/gold clothes, hairstyles and warm natural light. Upper-body busts holding blue-backed cards, matched size and baseline; whole head, hair, shoulders and hands visible. Remove scenery, table, text and interface. Genuine transparent alpha, no overlap, no frame, no text.

### landlord_table_wood.png

Seamless square PBR base-color map derived from the reference tabletop material. Flat top-down natural warm medium tawny-brown timber with subtle fine grain and gentle organic whorls, smooth polished wood, low contrast. Uniform diffuse wood color only: no perspective, table edge, letters, logos, cards, buttons, baked highlights, shading, vignette, yellow stripes or periodic sine-wave bands. The 3D renderer supplies its own lighting.

## 项目用法

Garden is the landscape background; opponents are transparent decoration; wood is the original shared table mesh's playing-surface material. All playing cards use the shared actual 3D card model and procedural canonical card faces. Free cosmetic selections do not create new model copies.

## 2026-10-09 用户提供的操作按钮

`button_double.png`（加倍）、`button_play.png`（出牌）、`button_hint.png`（提示）、`button_pass.png`（不出）与 `button_decline_bid.png`（不抢）直接复制用户附件，均保留 2172×724 原始尺寸和透明 alpha；未重新生成或改写像素。

运行时使用 Godot `AtlasTexture` 按原图可见透明轮廓（alpha ≥ 0.01）保留额外 5 像素余量，避免远离按钮的 alpha=1 极淡残点影响尺寸；等比显示完整按钮和加倍的 2x 徽标。原有 `Button` 保留点击、阶段权限、鼠标与触控目标，图片不接收输入；悬停、按下和禁用状态通过整体颜色反馈。文字由原图显示，按钮语义文字保留用于辅助功能和已有自动操作检查。“抢地主”和双倍阶段的“不加倍”保留文字按钮，避免把“不抢”误用于加倍决定。
