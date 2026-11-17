# 小板凳象棋音频资产说明

## 背景音乐

- 项目规范文件：`bgm_chinese_guzheng_01.mp3`
- 中文说明：中国古筝背景音乐 01
- 原始本地文件：`C:\Users\Administrator\Downloads\u_ej49m6thqx-chinese-guzheng-1-308264.mp3`
- 导入方式：复制到项目资产目录，不修改原下载文件
- 用途：小板凳象棋默认对局背景音乐
- 备用背景音乐：`bgm_guofeng.wav`（项目程序化生成的原创国风 BGM）
- 授权说明：该 MP3 为用户本地提供资产；正式商业发布前由项目方统一确认其商用授权与署名要求。

## 音效

- 默认走棋音效：`sfx_chess_move_wood_01.wav`
- 中文说明：象棋木质走棋音效 01
- 原始本地文件：`C:\Users\Administrator\Downloads\res_move.wav`
- 源素材归档：`SourceAssets/Audio/ChineseChess/res_move_source.wav`
- 处理脚本：`tools/process-chess-move-sfx.py`
- 处理：去直流/60Hz高通、静音检测、瞬态增强、木质低频主体增强、轻度压缩、软限幅、-1 dBFS 峰值归一化
- 增强前：Peak -4.92 dBFS / RMS -36.34 dBFS
- 增强后：Peak -1.00 dBFS / RMS -24.71 dBFS
- SHA-256：`6B04CC9C0967F9DCC6E3D950B56DAE5B0D534FB79DE997739E0BE700943A362E`
- 备用走棋音效：`move_wood.wav`（项目原木质落子音效）
