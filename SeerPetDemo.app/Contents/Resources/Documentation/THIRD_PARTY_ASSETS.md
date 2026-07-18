# 第三方资源说明

`frames/idle` 的 16 帧 PNG 从赛尔号官方 1 号精灵战斗 SWF 的内部待机子动画中提取，作为应用首次启动时的内置待机。程序对其他编号也会在本机从对应官方 SWF 自动提取同类资源。

`frames/walk-left` 和 `frames/walk-right` 各 8 帧 PNG 来自赛尔号官方 1 号精灵地图 SWF 的 `left` / `right` 时间轴，以 4 倍分辨率直接渲染 SWF 矢量内容。程序会为其他编号自动下载并提取对应地图行走资源。

`frames/bag-front/1.png` 来自赛尔号官方 `groupFightResource/pet/1.swf` 的 `pet` 元件第 1 帧，是背包槽位和右侧预览使用的正面静态形象。程序会优先从本机游戏资源为其他编号提取同类首帧，并仅保留最终 PNG。

`AppIcon-1024.png` 和 `AppIcon.icns` 使用 300 号精灵官方战斗 SWF 的内部待机动画第 16 帧制作，仅做透明边界裁切、居中和尺寸缩放。

`PetBagLegacy.png`、`PetBagButtons` 和 `PetBagSlots` 从本机赛尔号游戏目录的 `serverFile/resource/ui2.swf` 提取。背景使用怀旧精灵背包符号 `PetBagMc`（characterId 1707），移除了底部提示语、左上切换按钮、图鉴按钮和底部按钮的静态副本；按钮目录保存原控件的普通与悬停状态。槽位目录保存 `bgBtnB`（characterId 5534）和 `bgBtnY`（characterId 5730）的普通/选中帧。

`PetBagInfo` 同样从本机 `ui2.swf` 提取：右侧数据面板来自 `PetBagMc.infoMc`（characterId 1656），仅覆盖移除了左上角红色徽章；技能槽来自 `ui_Normal_PetSkilBtn`（characterId 4694），关闭按钮来自 characterId 1227。字段名称、坐标与显示逻辑依据原客户端 `PetDataPanel.as` 复原。

`PetTypeIcons` 从同一 `ui2.swf` 的 `Icon_PetType_*` 按钮类批量提取，内置 119 个正常状态 PNG；`PetGenderIcons` 来自 `PetGenderIcon`（characterId 31）的三帧原版图标。资源仅裁掉透明留白，右侧面板和技能槽保持原始图案比例，悬停可查看属性或性别名称。

`PetStats.plist` 是从原客户端嵌入的 `PetXMLInfo` 官方精灵配置中抽取的紧凑索引，仅保留编号及 `Atk`、`Def`、`SpAtk`、`SpDef`、`Spd`、`HP` 六项基础属性，用于在没有赛尔号服务器培养存档时保持原版属性顺序和官方基础值。

`PetNames.plist` 从官方客户端 `monsters.json` 配置中抽取，仅保留精灵编号与 `DefName`，用于新建桌宠时自动填写官方名称。配置解析参考 [WhY15w/seer-unity-config-parser](https://github.com/WhY15w/seer-unity-config-parser)。

`PetMeta.plist`、`PetMoves.plist` 和 `PetTypes.plist` 是同一官方客户端配置的紧凑索引：分别保留精灵属性、性别、进化和已学技能关系，技能名称/威力/PP/类别，以及属性中文名称。原版字段和技能替换流程依据 `PetDataPanel.as` 与 `SkillModule.as` 复原；桌宠没有赛尔号服务器培养存档，因此携带技能改为按桌宠实例保存在本机。

- 官方资源格式：`https://seer.61.com/resource/fightResource/pet/swf/{编号}.swf`
- 官方背包形象资源：`https://seer.61.com/resource/groupFightResource/pet/{编号}.swf`
- 官方 UI 资源：`https://seer.61.com/dll/UI.swf`
- 本地 UI 资源：`~/Library/Application Support/seer-game/serverFile/resource/ui2.swf`
- 1 号精灵待机子动画：`DefineSprite_15`
