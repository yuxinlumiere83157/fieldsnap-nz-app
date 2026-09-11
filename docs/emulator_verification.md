# 模拟器验证记录 — FieldSnap NZ Iteration 0

日期：2026-09-11（NZST）。执行人：Robin Huang（AI 辅助）。

**这份记录只证明"在 Android 模拟器上跑通了"**，不代表真机结果，也不代表任何性能/准确率目标。
性能目标（NFR2）和包体目标（NFR4）本轮完全未测量：debug 构建的数字不是那两个指标的口径。

## 1. 模拟器环境（实际检测）

| 项目 | 实际值 |
| --- | --- |
| AVD 名称 | `fieldsnap_api36` |
| 设备档案 | `pixel_6`（1080×2400, density 420） |
| 系统镜像 | `system-images;android-36;google_apis;arm64-v8a` |
| Android 版本 | 16（API 36） |
| ABI | `arm64-v8a` |
| 机型标识 | `sdk_gphone64_arm64` |
| 内存调整 | `hw.ramSize` 2048 → 3072 MB，`vm.heapSize` 228 → 384 MB |
| 序列号 | `emulator-5554` |

创建命令（可复现）：

```sh
SDK="$HOME/Library/Android/sdk"
export ANDROID_HOME="$SDK" ANDROID_SDK_ROOT="$SDK" JAVA_HOME="$(/usr/libexec/java_home -v 21)"
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "emulator" "system-images;android-36;google_apis;arm64-v8a"
echo no | "$SDK/cmdline-tools/latest/bin/avdmanager" create avd -n fieldsnap_api36 \
  -k "system-images;android-36;google_apis;arm64-v8a" -d pixel_6 --force
"$SDK/emulator/emulator" -avd fieldsnap_api36 -no-snapshot-load -no-boot-anim -gpu auto -no-audio
```

本轮新增的 SDK 组件：`cmdline-tools`（latest, 19.0）、`system-images;android-36;google_apis;arm64-v8a`。
`platform-tools` 与 `emulator` 原本已存在；`flutter doctor` 之前报的 “cmdline-tools missing” 现已补齐。

## 2. 测试素材

推送三张自制的纯色测试图（内容为程序生成，无版权问题），供 Photo Picker 选择：

```sh
adb shell mkdir -p /sdcard/Pictures/FieldSnap
adb push red_1280x960.jpg green_1280x960.jpg blue_1280x960.png /sdcard/Pictures/FieldSnap/
adb shell content query --uri content://media/external/images/media --projection _display_name
```

## 3. 执行步骤与真实结果

自动化脚本 + 截图 + logcat 记录见 `docs/logs/emulator_verification_20260911.log`。

| # | 操作 | 观察到的实际结果 | 判定 |
| --- | --- | --- | --- |
| 1 | 安装 debug APK 并启动 | `Performing Streamed Install / Success`；`topResumedActivity=nz.fieldsnap.app/.MainActivity`；APK 内 `minSdkVersion:'26'`、`targetSdkVersion:'36'` | verified |
| 2 | 初始界面 | 预览为空、`Select image` 可点、`Clear selection` 与 `Identify species (model missing)` 均禁用，无物种/置信度文案 | verified |
| 3 | 点 `Select image` | 真实系统 Photo Picker 启动：`topResumedActivity=com.google.android.photopicker/com.android.photopicker.MainActivity`；界面显示三张样本图与 "FieldSnap NZ will only have access to the photos you select" | verified |
| 4 | 选择一张图 | 回到 App；`MediaProvider: Open with lower FS for /storage/emulated/0/Pictures/FieldSnap/green_1280x960.jpg. Uid: 10198`；界面显示 `File: 18.jpg`、`Size: 32.8 KB`、`Pixels: 1280 x 960 px`；`Replace image` / `Clear selection` 变为可用 | verified |
| 5 | 点 `Replace image` 再选另一张 | 预览整体替换为新图，未出现叠加或残留；文件信息随之更新 | verified |
| 6 | 再开 Picker 后按返回键取消 | 焦点回到 `nz.fieldsnap.app/.MainActivity`，截图的 SHA-256 与取消前**完全一致**（`9cd9a4bd5a46c0d8…`），说明已选图片未被取消操作破坏 | verified |
| 7 | 点 `Clear selection` | 回到空状态：`No image selected yet`，识别按钮重新禁用 | verified |
| 8 | 全程崩溃/Flutter 异常扫描 | `adb logcat` 中 `FATAL EXCEPTION` / `E/flutter` / `ANR in nz.fieldsnap.app` 匹配行数 = **0** | verified |

注：第 4 步我原本预期点到"蓝色"那张，实际选中的是绿色的 `green_1280x960.jpg`——Picker 网格的落点与我预估的格子不一致。以实际日志与截图为准，这也是我保留原始 logcat 行的原因之一。

## 4. 截图证据

| Screenshot | SHA-256 (first 16) | What it shows |
| --- | --- | --- |
| `docs/logs/emulator_01_initial.png` | `042655ba165ad7b5…` | initial state: empty preview, recognition disabled, hint text present |
| `docs/logs/emulator_02_picker.png` | `e11a43ec594ec770…` | real system Photo Picker (com.google.android.photopicker) with the three pushed samples and the 'only the photos you select' notice |
| `docs/logs/emulator_03_preview.png` | `a59a99e8e997b524…` | returned result rendered: green sample 18.jpg, 32.8 KB, 1280x960 px; Replace/Clear now enabled |
| `docs/logs/emulator_04_replaced.png` | `9cd9a4bd5a46c0d8…` | after Replace: distinct image shown, whole preview replaced (no stacking) |
| `docs/logs/emulator_05_after_cancel.png` | `9cd9a4bd5a46c0d8…` | after pressing Back in the picker: byte-identical to the previous screenshot, so the chosen image survived cancellation |
| `docs/logs/emulator_06_cleared.png` | `dcbeb9eea4dd147d…` | after Clear selection: back to the empty state, recognition disabled again |

截图不含账号、设备序列号或无关路径；机型标识 `sdk_gphone64_arm64` 只是模拟器通用名称。

## 5. 本轮仍未验证的内容（不要当作业绩）

- **真机**：M1 §6 要求的 ARM64 物理设备与 Android 15 主测试系统都还没跑过；模拟器不能替代。
- **推理延迟 / 内存**：没有模型，无法测；且 NFR2 要求 profile/release 包 + 真机 + 预热后 ≥30 次运行。
- **release 包体**：未构建 release AAB/APK，NFR4 未测。
- **读取失败的错误面板**：单元/组件测试已覆盖该分支，但模拟器上未演示（该分支需要文件在选中后被删除或读取失败）。
- **相机拍摄**：FR1 的后半段尚未实现。
- **Photo Picker 的“无照片/权限被撤销”分支**：未构造该场景。

## 6. 复现步骤（真机版，供你操作）

1. 手机开启开发者选项与 USB 调试，用数据线连接并在手机上同意授权。
2. `export PATH="$HOME/development/flutter/bin:$PATH"`；`export ANDROID_HOME="$HOME/Library/Android/sdk"`；`export JAVA_HOME="$(/usr/libexec/java_home -v 21)"`。
3. `flutter devices` 应能看到你的手机；然后 `flutter run -d <device-id>`。
4. 按第 3 节表格的 1–8 步逐项操作，并记录手机型号、Android 版本与观察结果。
5. 把结果追加到 `docs/progress.md`，并在 `docs/traceability.md` 中把 "on-device run" 一行从 `not run` 改为实测结论。
