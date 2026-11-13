# CodecPack-DSM

> 让 DSM 7.2.2+ 重新拥有 **HEVC / H.264 / AAC** 编解码能力的替换套件（SPK）。
> 用官方 AME 3.1.0 的激活组件 + **FFmpeg 9.0.2** 重新组装成 `CodecPack`，直接顶替 Advanced Media Extensions。

**当前版本：99.0.0-9999** ｜ 已实测：`DSM 7.4-90075 / x86_64`（也提供 aarch64 包）

---

## 背景

Synology 从 **AME 4.0（DSM 7.2.2）** 起把 HEVC/AVC 的编解码器从 Advanced Media Extensions
里抽走，改成要登录 Synology 账号领取授权，Surveillance Station 的 H.265 还要另外买
Surveillance Video Extension。结果是：

- Media Server / Video Station 不再能播放或转码 HEVC
- Synology Photos 不再为 HEVC 视频生成缩略图
- 命令行 `ffmpeg41` 相关能力一起消失

本项目的思路：**AME 3.1.0 的组件本身是完好的，只是被 license 校验锁住了**。
所以解出 3.1.0 的包，把校验函数改成永远返回 true，再补一个真正能编解码的 FFmpeg，
按官方目录结构重新打包。DSM 那边看到的就是一个正常安装、已激活的 CodecPack。

## 成品

| 文件 | 大小 | 平台 |
|---|---|---|
| `CodecPack-x86_64-99.0.0-9999.spk` | 97 MB | Intel / AMD（`x86_64`） |
| `CodecPack-aarch64-99.0.0-9999.spk` | 82 MB | `rtd1296` / `rtd1619b` / `armada37xx` |

内含：

| 组件 | 版本 | 说明 |
|---|---|---|
| FFmpeg | **9.0.2**（`n9.0.2-57-gd838f9f9ae-20261113`） | 来自 [FFmpeg-Builds](https://github.com/FFmpeg-Builds/FFmpeg-Builds) GPL 静态包 |
| libx264 / libx265 | 随包 | H.264 / HEVC 编解码 |
| aom / dav1d / vpx / opus / lame / vorbis … | 随包 | AV1/VP9/音频 |
| `libsynoame-license.so` | AME 3.1.0-3005 | 已 patch，5 个校验函数恒返回 1 |
| glibc | 2.28（Debian 10） | 随包携带，见下文"为什么要带 glibc" |

## 安装

SSH 上去，先卸官方包，再装替换包：

```sh
sudo synopkg uninstall CodecPack
sudo synopkg install /path/to/CodecPack-x86_64-99.0.0-9999.spk
```

包是纯文件包（`startable="no"`），`conf/privilege` 只声明 `{"defaults": {"run-as": "package"}}`，
不申请 root、不带 SUID，所以**不需要 Synology 签名**就能装，装完即刻生效。

> 如果 postinst 没有权限写激活文件，它会打印一行 `sudo` 命令，照着执行即可。

## 验证

仓库自带 `verify.sh`，也可以直接跑：

```sh
/var/packages/CodecPack/target/bin/ffmpeg41 -version
/var/packages/CodecPack/target/bin/ffmpeg41 -encoders | grep -E 'libx265|libx264'
```

实测数据（DSM 7.4-90075 / x86_64）：

| 项目 | 结果 |
|---|---|
| `ffmpeg41 -version` | `ffmpeg version n9.0.2` ✅ |
| 1080p HEVC 编码 | 3 秒素材 → 1.8 MB ✅ |
| HEVC 解码出一帧 JPEG（缩略图路径） | **0.146 s** ✅ |
| `libx265` / `libx264` | 均在 ✅ |
| 激活文件 / `pack_status.conf` | `{"status": "installed"}` ✅ |

## 工作原理

### 1. 解开官方加密 SPK

Synology 的 SPK 是 `0xADBEEF` 魔数 + msgpack 头 + **Ed25519 签名** +
**XChaCha20-Poly1305 secretstream** 加密的条目。`decrypt_spk.py` 用公开的
签名公钥/主密钥校验并解出 `package.tgz`（密钥来源：SynoXtract / synodecrypt）。

### 2. 打掉许可证校验

从 AME 3.1.0 里取出 `libsynoame-license.so`，在固定偏移覆写机器码，
让 5 个函数无条件返回 true：

| 架构 | 偏移 | 写入 |
|---|---|---|
| x86_64 | `0x9144 0x9234 0x9614 0x9804 0xbe74` | `B8 01 00 00 00 C3`（`mov eax,1; ret`） |
| aarch64 | `0x74c4 0x75f0 0x7a10 0x7c00 0xa220` | `20 00 80 52 C0 03 5F D6`（`mov w0,#1; ret`） |

被 patch 的函数：`IsValidStatus`、`ValidateLicense`、`CheckLicense`、
`CheckOfflineLicense`、`SLIsXA`。改前/改后各校验一次 MD5，任何一步不对就中止构建。

### 3. 用 FFmpeg 9.0 当后端

官方 AME 3.1.0 的包里**并不带** ffmpeg 二进制（激活后才下载 codec pack），
所以这里直接放 FFmpeg-Builds 的 9.0 GPL 包：`ffmpeg41` + `ffprobe`，
再按官方布局建好 `bin/ffmpeg41`、`bin/ffmpeg33-for-surveillance` 等符号链接。

### 4. 为什么要带 glibc（重点）

FFmpeg-Builds 的 Linux 包**不是全静态**：codec 库是静态链接的，但运行时仍依赖
glibc，且要求 **≥ 2.28**（`statx`、`renameat2`、`fcntl64@2.28`、`tss_*`、`glob@2.27`）。
DSM 7 只有 **glibc 2.26**，原样装进去必然报：

```
ffmpeg41: /lib/libc.so.6: version `GLIBC_2.28' not found
```

所以包里自带一套 glibc 2.28 运行时（8 个 .so，约 3.9 MB），并用 `patchelf` 把
二进制改指向它：

```
interpreter  /var/packages/CodecPack/target/pack/lib/glibc/ld-linux-x86-64.so.2
RPATH        $ORIGIN/../lib/glibc     ← 强制 DT_RPATH，LD_LIBRARY_PATH 抢不走
```

`ffmpeg41` 仍然是普通 ELF：没有 shell wrapper、不用设环境变量、也不可能误加载
DSM 的老 libc。选 2.28 而不是更新的版本，是因为它正好是这份二进制要求的下限，
在 DSM 7 的 4.4 内核上最稳。

### 5. 让 DSM 认出这个包

DSM 7.4 的 `synothumb` / `synomkflvd` / `synoflvconv` 会检查：

```
/var/packages/CodecPack/target/pack/HAS_HEVC
/var/packages/CodecPack/target/pack/HAS_H264
/var/packages/CodecPack/target/pack/HAS_AAC
/var/packages/CodecPack/target/pack/HAS_VC1
```

**这些空文件就是"这个 codec pack 提供哪些编码"的声明**（官方 SVE 包里也有一个
空的 `pack/HAS_H264`）。缺了它们，媒体守护进程会认为包里什么都没有，继续走
`ffmpeg-thumb` 兜底——即使 `ffmpeg41` 本身完全可用。

## 目录结构

```
prepare.sh       下载 AME / FFmpeg-Builds 9.0 / glibc，解密、patch、strip
build_spk.sh     按架构组装 SPK（x86_64 | aarch64）
decrypt_spk.py   Synology 加密 SPK -> tar（需要 pysodium + msgpack）
verify.sh        装到 NAS 后跑这个自检
src/
├── INFO                     包元数据（arch 由构建时替换）
├── conf/privilege           run-as package，不申请 root
├── conf/resource            {}
├── scripts/                 preinst/postinst/postuninst/… 
└── package/
    ├── activation/          activation.conf + offline_license.json
    ├── bin/synocodectool    存根（exit 0）
    ├── usr/bin/             synoame-bin-check-license / -request-codec 存根
    ├── etc/settings.conf
    └── pack/                HAS_* 标记 + INFO（bin/lib 由构建时放入）
```

装好后的实际布局：

```
/var/packages/CodecPack/target/
├── bin/ffmpeg41              -> ../pack/bin/ffmpeg41
├── pack/bin/ffmpeg41         FFmpeg 9.0.2（解释器指向包内 glibc）
├── pack/bin/ffprobe
├── pack/lib/glibc/           ld-linux / libc / libm / libmvec / libpthread / …
├── pack/HAS_{HEVC,H264,AAC,VC1}
├── usr/lib/libsynoame-*.so   AME 3.1.0，license 已 patch
├── usr/bin/synoame-bin-*     存根
└── etc/activation/           activation.conf + offline_license.json
```

## 构建

```sh
./prepare.sh              # 幂等；约 40 MB 下载；解包 + patch + strip
./build_spk.sh x86_64
./build_spk.sh aarch64
```

依赖：`curl tar xz patchelf`、`binutils`（aarch64 还需要 `aarch64-linux-gnu-binutils`）、
`python3` + `pysodium` + `msgpack`（没有的话会自动用 `uv run` 装临时环境）。

`prepare.sh` 会在 patch 后校验 MD5，和钉死的值不一致就退出——这样 Synology 哪天
悄悄换了包，构建会立刻失败而不是产出一个坏包。

## 兼容性

| 平台 | 状态 |
|---|---|
| DSM 7.4 / x86_64 | ✅ 实测（GeminiLake 类机器） |
| DSM 7.2.2+ / x86_64 | ✅ 应可用（`os_min_ver=7.2-60110`） |
| DSM 7.2.2+ / aarch64（rtd1296/rtd1619b/armada37xx） | ⚠️ 已构建，qemu 下跑通，未上真机 |
| DSM 7.0 / 7.1 | ❌ 不需要（官方 AME 3.x 本来就正常），且 `package.tgz` 用 xz 可能不认 |

## 已知限制

- **纯软件编解码**，没有把 VAAPI/QSV 接进 AME 的调用路径。ARM 机型跑 1080p 以上会很吃力。
- `package.tgz` 用 **xz**（与官方 AME 3.1.0 一致），所以 `os_min_ver` 定在 7.2。
- Synology Photos 只用 CodecPack 生成缩略图；浏览器里播放 HEVC 仍取决于浏览器本身。
- Photos / Video Station 的 UI 级效果未做端到端验证（测试机上没有照片库）。

## 法律与分发

- `libsynoame-license.so` 是 **Synology Inc. 的财产**，本项目对其做了二进制修改。
  仓库保持 **private**，不公开发布、不再分发。
- FFmpeg-Builds 的 GPL 构建 + Synology 私有二进制混在一个包里，**不具备再分发条件**。
- 仅限自用。请自行确认所在地区的合法性。

## 变更记录

- **99.0.0-9999** — 首个版本：FFmpeg 9.0.2 + 包内 glibc 2.28 + AME 3.1.0 激活组件；
  补上 `pack/HAS_*` 标记，使 DSM 媒体守护进程认可包内编码能力。
