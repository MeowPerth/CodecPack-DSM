# NOTICE

本项目（CodecPack-DSM）不是一个可以自由分发的开源软件。

## 第三方与专有组件

1. **`libsynoame-license.so` / `libsynoame-*.so`**
   来自 Synology Advanced Media Extensions 3.1.0-3005，版权归 **Synology Inc.**
   所有。其中 `libsynoame-license.so` 在本项目的构建流程中被修改（5 处二进制
   patch，使许可证校验函数恒返回 1）。修改后的二进制**不得再分发**。

2. **FFmpeg 9.0.2**
   取自 [FFmpeg-Builds](https://github.com/FFmpeg-Builds/FFmpeg-Builds) 的
   `linux64-gpl` / `linuxarm64-gpl` 构建，基于 FFmpeg 并以 `--enable-gpl`
   编译（x264/x265 要求）。该二进制同时受 GPL 与其中各库的许可证约束。

3. **glibc 2.28**
   取自 Debian 10（`libc6` / `libgcc1`），按 LGPL 使用，仅作为运行时随包携带。

4. **SPK 骨架、构建脚本**
   派生自 [renaudallard/synology_codecs](https://github.com/renaudallard/synology_codecs)
   的 CodecPack 部分，按其 "provided as-is for personal use" 的声明使用。

## 分发限制

由于上述专有组件与 GPL/非自由许可的混合，**本仓库及其构建产物不具备再分发条件**：

- 仓库设为 private，不公开、不发布到公共镜像
- Release 中的 `.spk` 仅供仓库所有者自用
- 请勿将 `.spk` 或其中的 Synology 二进制上传到任何公开位置

## 免责

仅供个人在自有设备上恢复被移除的编解码能力使用。使用者需自行确认所在地区
法律法规与 Synology 软件许可条款。作者不对任何后果负责。
