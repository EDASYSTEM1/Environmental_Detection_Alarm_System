# docs/ 文档索引

> 本目录放"给人看"的东西：接口、分工、引脚、组规、波形图。
> 代码在 `top/` `common/` `modules/`，脚本在 `scripts/` `tools/`。

## 哪个文件是"唯一依据"

| 文件 | 地位 | 谁会改 |
|---|---|---|
| **`接口协议.md`** | ★ **唯一依据**（端口/数据格式/开关映射/显示规范） | 只有组长，且要连同 `sys_top.v` 一次提交 |
| `团队约定.md` | ★ 组规（每人只改自己目录、接口冻结、时钟复位等） | 组长，组内讨论后 |
| `分工与流程.md` | 分支模型、PR 清单、每日流程 | 组长 |
| **`引脚分配.md`** | 引脚表 + Pmod 接线说明 | ⚠️ **自动生成**，改 `xdc/sys_pins.xdc` 后跑 `tools/gen_pin_doc.py`，不要手改 |

## 两份正式文档的"源 + 导出物"

| 源文件（改这个） | 导出物（别直接改） | 用途 |
|---|---|---|
| `接口协议.md` | `接口协议_v1.1.docx` / `.pdf` | 端口/数据格式/开关映射；发群、打印 |
| `引脚分配.md`（由 xdc 生成） | `引脚分配_v2.0.docx` / `.pdf` | 全部引脚 + Pmod 接线；硬件调试、报告附录 |

> ⚠️ **规则**：只改 `.md`（引脚表则改 `xdc` 后重新生成），再重新导出 docx/pdf。
> 直接改 docx 会让几个版本不一致，组员拿到的可能就是旧版本。

## 生成命令（都在仓库根目录执行）

```bat
:: 引脚表：从 xdc 重新生成 md（改了引脚才需要）
python tools\gen_pin_doc.py

:: md → docx（需要 python-docx；再转 pdf 交给组长用 office 工具导出）
python tools\md2docx.py docs\引脚分配.md docs\引脚分配_v2.0.docx

:: 波形图：Icarus 仿真 → VCD → PNG
tools\wave\run_wave.bat
```

## 波形图

| 文件 | 内容 |
|---|---|
| `waveforms\uart_8n1.png` | UART 8N1 发送 0xA5 的位时序（含比特边界） |
| `waveforms\oled_spi.png` | Pmod OLED（SSD1306）SPI 初始化时序 |

## 版本历史

| 文档 | 版本 | 变更 |
|---|---|---|
| 接口协议 | v1.0 | 四模块端口冻结、数据格式、开关映射 |
| 接口协议 | v1.1 | 订正 ALS 为 8 位 ADC；补 UART 上报（4.6）；`disp_ctrl` 增加 `sensor_status`；显示布局对齐实现 |
| 引脚分配 | v1.1 | 补 Pmod 接线说明、订正 HYGRO/ALS 引脚 |
| 引脚分配 | v2.0 | 改为从 `xdc` 自动生成；修掉编号重复、JD 归位；补模块引脚对照表 |
