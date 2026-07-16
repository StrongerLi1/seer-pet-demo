# 第三方资源说明

`frames/idle` 的 16 帧 PNG 从赛尔号官方 1 号精灵战斗 SWF 的内部待机子动画中提取，作为应用首次启动时的内置待机。程序对其他编号也会在本机从对应官方 SWF 自动提取同类资源。

`frames/walk-left` 和 `frames/walk-right` 各 8 帧 PNG 来自赛尔号官方 1 号精灵地图 SWF 的 `left` / `right` 时间轴，以 4 倍分辨率直接渲染 SWF 矢量内容。程序会为其他编号自动下载并提取对应地图行走资源。

`AppIcon-1024.png` 和 `AppIcon.icns` 使用 300 号精灵官方战斗 SWF 的内部待机动画第 16 帧制作，仅做透明边界裁切、居中和尺寸缩放。

- 官方资源格式：`https://seer.61.com/resource/fightResource/pet/swf/{编号}.swf`
- 1 号精灵待机子动画：`DefineSprite_15`
