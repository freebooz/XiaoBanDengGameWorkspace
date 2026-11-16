# 麻将桌面语音

青年女声、中年男声和长辈女声各有 30 段。三套均为普通话，包含万、筒、条的 27 种牌名和碰、杠、胡。「一条」播报为「幺鸡」。默认青年女声，玩家可以在声音设置中切换，游戏从本地资源播放。

## 制作

通过 OpenBMB 官方免费演示的 VoxCPM2 语音设计生成三名虚拟角色。先按年龄和音色描述合成一段角色参考，再用其稳定各短句的音色。碰采用短促上扬的语气，杠加重语气，胡更欢快，普通报牌清楚利落。参考音频也由同一模型生成，未上传真人录音。资源经去除静音余量、轻微高通和防爆音处理，以 24 kHz 单声道 PCM WAV 打包。模型及依赖仅用于制作。

相关模型对照中，Qwen3-TTS 具有描述式音色控制，CosyVoice 3 提供多种中文方言示范。选用 VoxCPM2 是因为其公开演示可实际使用，并能直接以年龄、音色、情绪和语速描述合成原创新声音。此制作未验证贵阳方言。模型卡将 VoxCPM2 的模型标为 Apache 2.0。

- [OpenBMB 官方 VoxCPM2 模型卡](https://huggingface.co/openbmb/VoxCPM2)
- [OpenBMB 官方公开演示](https://huggingface.co/spaces/openbmb/VoxCPM-Demo)
- [Qwen3-TTS 技术报告](https://arxiv.org/abs/2601.15621)
- [CosyVoice 3 技术报告](https://arxiv.org/abs/2505.17589)
