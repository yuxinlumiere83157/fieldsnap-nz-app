# Notion record — drop-in update for "COMP826｜FieldSnap NZ｜M2 Development Record｜2026 S2"

Prepared 2026-09-11. The Notion page was read in full (207 blocks) so this material fills the factual
gaps without touching the existing narrative. Paste each section where indicated; the three existing
empty tables are filled with the table blocks below.

Frozen artefacts referenced throughout: FP32 model, 20 classes, production preprocessing, FR2
(0.26 / 0.89 / 100.0), FR4 (0.37, margin off), and the one-shot sealed-test results.

---

## A. Fill the empty table under "M1 主要验收目标"

| M1 target | 目标值 | 实测（sealed test, 187 张） | 结论 |
| --- | --- | --- | --- |
| Held-out top-1 accuracy | ≥ 0.80 | **0.5561** | **未达到** |
| Held-out top-3 accuracy | ≥ 0.95 | **0.7968** | **未达到** |
| Macro-F1 | ≥ 0.80 | **0.5343** | **未达到** |
| Accepted accuracy @ coverage ≥ 0.70 | ≥ 0.90 | **0.6496 @ 0.7326** | **未达到** |
| Inference latency (Pixel 8, profile, 30 runs) | median ≤ 300 ms, P95 ≤ 500 ms | median **101.65 ms**, P95 **155.27 ms** | **达到** |
| Release package size | ≤ 80 MB | APK **76.3 MB**, AAB 72.0 MB | **达到** |
| Model size | ≤ 15 MB | FP32 **3.60 MiB** | **达到** |
| Offline operation | 必须离线可用 | radios off 下完整流程通过 | **达到** |
| Local history persistence | 必须持久化 | 强杀重启后数据库 hash 与记录不变 | **达到** |

每条均为实测值；未达到的目标如实记录，事后未调整目标、未移动冻结阈值。

## B. Fill the empty table under Checkpoint 1D（受控扩数据实验）

| 配置 | Validation top-1 | Validation top-3 | Macro-F1 |
| --- | --- | --- | --- |
| 小数据集（849 train） | 0.4479 | 0.6748 | 0.4239 |
| 扩展数据集（2,995 train） | **0.5031** | **0.7485** | **0.4993** |
| 变化 | +0.0552 | +0.0737 | +0.0754 |

只改变训练数据；模型架构、解冻层数、learning rate、validation 与 sealed test 全部保持不变。

## C. Fill the empty table under "Final sealed test：一次性打开并冻结"

| 指标 | 实测 | M1 目标 | 结论 |
| --- | --- | --- | --- |
| Top-1 accuracy | **0.5561** | ≥ 0.80 | **NOT MET** |
| Top-3 accuracy | **0.7968** | ≥ 0.95 | **NOT MET** |
| Macro-F1 | **0.5343** | ≥ 0.80 | **NOT MET** |
| Accepted accuracy | **0.6496** | ≥ 0.90 @ coverage ≥ 0.70 | **NOT MET** |
| Coverage | **0.7326**（137 accepted / 50 rejected） | ≥ 0.70 | MET |
| Rejected-subset top-1 | 0.3000 | — | 仅作透明度报告 |

Provenance：model SHA-256 `e6b10afdfc97d73d…`、test manifest SHA-256、run id
`20260911T191603-e6b10afd`、commit、timestamp 均记录在
`docs/final_test_evaluation_report.md` 与 `artifacts/final_test_evaluation.json`。

## D. 新增小节：Iteration 4 — 可用性评估准备（尚未开始测试）

**状态**：协议 **v1.2** 已冻结（2026-10-02 由 v1.1 修订：招募目标改为五人，主任务刺激图更换，
分析脚本支持增量摄入）；**未招募、未测试任何参与者，仓库中不存在任何参与者数据**；完成了一次
facilitator 演练（不计入参与者数据）。

**冻结方式**：`docs/usability/FREEZE_v1.2.md` 记录 13 个套件文件的 SHA-256（v1.1 记录保留为历史），
并声明 C1–C3、三个任务、critical error 定义、排除规则与 SUS 措辞在首场之后不得修改（改动即 v1.3）。
`tools/usability/verify_kit_freeze.py` 可随时复核，任何冻结件被改即非零退出。

**三个任务**

1. 完成首次识别并打开 learning card（**主任务**）
2. 遇到 unsuitable / Uncertain 结果并用另一张照片恢复
3. 找到并删除一条 history 记录

**记录字段**：每个任务的成功、完成时间、错误、facilitator 介入次数、critical error。

**Critical error 定义（预先固定，避免事后放宽）**：①卡死无法继续；②界面给出不实状态；
③无警告的数据丢失。慢或困惑**不算** critical error。

**预注册成功判据**：C1 ≥ 90%（在五人目标下即 **5/5**）无介入完成主任务；C2 平均 SUS ≥ 70；
C3 critical error = 0。**不足五人时只报中期单人结果，C1–C3 标注为尚不可评估**，不得据此宣称达标或未达标。

**SUS**：标准 10 题原文，奇数题 `x−1`、偶数题 `5−x`、求和 ×2.5；facilitator 逐题逐字朗读，
被试私下填答。**任一题缺失即该问卷失效**（标准不允许部分计分），并会明确报告失效数量。

**三个定性问题**：最困惑的地方；你认为 "Uncertain" 是什么意思；最想先改什么。

**崩溃处理**：崩溃或卡死计为**任务失败 + critical error**，不计为排除；只有设备层面故障或退出
同意才排除，且必须报告。

**每次会话前的清洁重置**（`docs/usability/reset_checklist.md`）：`pm clear` → 撤销相机权限 →
清空相册 → 只推送两张固定任务图 → 重扫媒体 → 确认"未选图 + 空历史"。

**固定任务图**：`docs/usability/task_images/task1_subject.jpg`（来自我们自己的 CC0 验证集照片，
来源记录在 `PROVENANCE.md`）与 `task2_unsuitable.jpg`（可复现生成的"拍屏幕"废图），
两位参与者看到完全相同的素材。

## E. 新增小节：Independent audit remediation（Phase A/B）

审计作为缺陷报告处理，但**每个代码缺陷都先在旧代码上独立复现再修**。

| # | 发现的缺陷 | 复现方式 | 处理 |
| --- | --- | --- | --- |
| 1 | 换图后旧识别结果残留（species / confidence / latency 未清） | 先写 3 个回归测试，在旧代码上全部失败（`Expected ResultKind.none / Actual identified`） | 清空全部派生字段 + 用 selection generation 阻止在途结果落到新图 |
| 2 | 分类进行中换图，旧结果可能挂到新图 | 同上第 2、3 个回归测试 | 同上 |
| 3 | **JPEG EXIF double-orientation** | 用新生成的 JPEG 夹具复现（PNG 路径 8 种取向全对、JPEG 除 1 外全错）；根因：`image` 包的 JPEG 解码器自己已应用取向，PNG 解码器不会 | 检测解码器是否已补偿后跳过；PNG 路径未改 |
| 4 | 可用性解析器会把空白模板当成成功被试 | 用真实空白模板跑解析器 | 只接受精确 yes/no；缺失 SUS 即问卷失效；无有效问卷时 exit 2 且不产出报告 |

**审计对冻结评估的影响：无——这是实测结论，不是假设。** 对 187 张已评估测试图做**仅元数据**扫描
（`artifacts/exif_orientation_audit.json`）：186 张 JPEG + 1 张非 JPEG，**APP1 段 0 个、EXIF APP1 段 0 个**，
取向直方图 `{1: 187}`。整个测试集没有任何 EXIF 段，取向变换从未执行，因此修复前后 187 张的输入
张量完全相同。扫描过程未跑分类、未重算任何指标。

审计中**没有被驳回的发现**：两项代码缺陷均被独立复现。

## F. 新增小节：隐私整改与仓库迁移

| 项目 | 处理 |
| --- | --- |
| 已发布数据清单中的精确/近似观测位置（`latitude` / `longitude` / `place_guess`） | 列已删除；抓取脚本不再记录，清单生成脚本主动剥离 |
| 真机序列号（出现在 2 处文档） | 已移除；内存采样脚本改为默认脱敏 |
| 旧仓库 `fieldsnap-nz` | **设为 private + archived**；匿名访问返回 404；保留作个人审计底稿 |
| 新公开提交仓库 | `fieldsnap-nz-app`，**单一根提交、不含任何旧历史**，因此旧隐私内容不会随历史带出 |
| 仓库内其他个人信息 | 无姓名、无学号、无账号、无本地绝对路径；`AGENTS.md` 已改为中性的 `ENGINEERING_RULES.md` |
| AI 声明 | 保留事实（作者在 AI 编程辅助下完成，全部内容经作者审阅与验证），**不出现具体工具名** |
| 参与者数据 | 协议与模板中说明：仅匿名聚合结果与去标识化引文可出现在受评报告与公开文档中；默认不录音 |

## G. 需要修正/补充的其余事实（相对于当前 Notion 记录）

* **Iteration 2 之后新增的真机相机验证**：capture / cancel / permission denial + recovery /
  gallery fallback 四项均已在 Pixel 8 真机执行（`docs/physical_camera_verification.md`）。
* **离线端到端**：`cmd connectivity airplane-mode enable` 只改标志位，Wi-Fi 仍开着、`ping` 仍通；
  真正离线需 `svc wifi/data disable` 并三重验证（`wifi_on=0`、无默认网络、`ping` 不可达）。
  离线完整流程与持久化验证见 `docs/physical_device_run_4.md`。
* **FR2 的另一处事实**：`maxBrightness` 的原始选取规则先后被修订两次（先选过 0.80，因代价 1.2%
  误拒而改；再选过 1.00，因使上限形同虚设而改），最终为 0.89。协议修订原文与实测理由都保留在
  `docs/quality_gate_calibration_protocol.md` 中，未删改历史。
* **新发现并修好的验证缺口**：契约测试原先只校验未提交的训练产物，全新 clone 上会 skip，
  意味着**发布模型的输入契约从未被验证**；现改为回退到 `assets/models/`。测试数
  **103 passed / 4 skipped**（4 个 skip 为 opt-in 校准 harness 与研究对照，依赖有意未公开的本地数据）。
* **全新 clone 验证**（`fieldsnap-nz-app`）：`pub get` 通过 → `analyze` clean → 确定性 103/4 →
  host 集成 8/1 → 套件冻结校验通过 → Android debug 构建成功。

## H. 尚未完成（如实列出，不包装）

1. **可用性测试本体**：未招募、未测试。
2. **INT8 掉约 19 个百分点的根因**：未诊断完成；FP16 / QAT 未做。
3. **reference vector 约 0.237 差异的根因**：仍为 unconfirmed hypothesis，最终报告须继续这样写。
4. **`third_party/tflite_flutter` 本地补丁**：仍存在，需等上游应用 Kotlin 插件后移除。
5. **"设备完全无相机应用"分支**：仅有 stub 测试覆盖，无真机验证。
6. **峰值内存**：仅 debug 构建观测值；release 未测。
7. **包体优化**：76.3 MB 已过 NFR4，但未做 per-ABI 拆分（可显著缩小）。
8. **M1 精度目标整体未达到**，已冻结为最终结果，不再重跑作为选择依据。
