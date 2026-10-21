# ⚡ mpv4all

> **The definitive, battle-tested MPV configuration**: Direct3D 11 Flip presentation, AI-driven hardware upscaling (NVIDIA RTX VSR & True HDR), a top-tier neural shader suite (FSR, NIS, SGSR, CAS), an OLED-optimized image viewer, and a real-time audiophile studio HUD.

---

## 🤖 Disclaimer: Welcome to the *Vibe Coding* Era

Let’s be straightforward: **this repository is no longer manually written line-by-line like in the old days.**  
`mpv4all` has officially transitioned into the **Vibe Coding** era.

Rather than wasting countless hours debugging ASS subtitle vector syntax, wrestling with deprecated Lua APIs, or grinding out GLSL matrix boilerplate by hand, this setup is architected at a high level and iteratively co-engineered, refined, optimized, and benchmarked alongside modern LLMs.

Human direction + machine acceleration = **zero syntax headache, cutting-edge rendering techniques, rock-solid stability, and pure visual excellence.**

---

## 🚀 Key Features

### 1. Elite Rendering Pipeline (`gpu-next` + D3D11 Flip Model)
* **Modern Video Output**: Built around `vo=gpu-next` with native `d3d11` API and context.
* **DXGI Flip Presentation (`d3d11-flip=yes`)**: Modern Windows presentation model delivering ultra-low latency, zero tearing, and eliminate micro-stuttering across windowed and borderless fullscreen modes.
* **Hardware Acceleration**: `hwdec=auto-safe` (D3D11VA) for seamless, hardware-assisted decoding.
* **Chroma & Dithering Excellence**:
  * Chroma scaler: **EWA Lanczos** combined with halo suppression (`cscale-antiring=0.7`).
  * Downscaling: Crisp, ringing-free **Mitchell-Netravali** (`correct-downscaling=yes`).
  * `sigmoid-upscaling=yes` to suppress ringing along high-contrast lines.
  * Dynamic, bit-depth matched temporal dithering (`dither-depth=auto`).
* **OLED Perfect Blacks**: Pure black letterbox & canvas bars (`#000000`) without gray clipping or washed-out letterbox borders.

---

### 2. Hardware AI Upscaling & Custom Shader Suite (Keys `1` – `5`)
Switch instantly between 5 state-of-the-art upscalers and edge reconstructors with single-key shortcuts:

| Key | Scaler / Technology | Description |
| :---: | :--- | :--- |
| **`1`** | **NVIDIA RTX Video Super Resolution (VSR)** | Hardware AI upscaling running on **RTX Tensor Cores** via `d3d11vpp`. Dynamically calculates the optimal aspect-preserving scale factor (clamped up to 4.0x) based on current window/display size. |
| **`2`** | **NVIDIA Image Scaling (NIS)** | Compute shader port (`NVScaler.glsl`) of NVIDIA's proprietary spatial scaler, featuring 6-phase directional filtering and adaptive unsharp masking directly on the luma plane. |
| **`3`** | **AMD FidelityFX FSR 1.0 (EASU + RCAS)** | Two-pass upscaler (`FSR.glsl`): Edge-Adaptive Spatial Upsampling (EASU) followed by Robust Contrast-Adaptive Sharpening (RCAS) with active deringing. |
| **`4`** | **Qualcomm SGSR v1** | Snapdragon Game Super Resolution (`SGSR.glsl`): Ultra-efficient single-pass directional edge scaler delivering remarkable edge definition. |
| **`5`** | **AMD CAS (Scaled Reconstruction)** | Contrast Adaptive Sharpening (`CAS-scaled.glsl`) with custom gamma relinearization (Rec.709/BT.1886) operating directly on the luma channel. |
| **`0`** | **Full Pipeline Reset** | Clears all active GLSL shaders, removes active VSR filters, and restores the pristine default Lanczos pipeline. |
| **`9`** | **Cycle Base Luma Scaler** | Quickly toggles fallback scaling between `nearest` and `lanczos`. |
| **`-`** | **Shader Status** | Displays the active GLSL shader chain directly on the OSD. |

---

### 3. Intelligent NVIDIA RTX Video True HDR (`autohdr.lua`)
* Toggled on/off instantly with **`h`**.
* Uses `d3d11vpp:nvidia-true-hdr` to perform real-time AI-based SDR-to-HDR tone expansion.
* **Double Tone-Mapping Prevention**: Inspects stream metadata (`PQ`, `HLG`, `bt.2020-ncl`, and peak signal limits) and **automatically skips injection** if the media is already native HDR, preventing blown-out highlights or crushed darks.

---

### 4. Audiophile Studio HUD & Signal Path Monitor (`audio-player.lua`)
A vector ASS dashboard designed for high-resolution audio, toggled via **`a`**, with two dynamic modes:

* **Album Art Mode (Floating Glass Capsule)**:  
  When an embedded album cover is present, the script renders a floating translucent capsule pinned to the top edge of the cover:
  * Track number/count, duration, title, artist, album, year, and ReplayGain values.
  * Quality badges: Lossless (Emerald Green) vs. Lossy (Warm Amber), true container format, bit depth, sample rate, and bitrate.
  * Current audio device output and signal path status.
* **Pure Audio Mode (Hi-Fi Studio Rack)**:  
  For pure audio files without artwork, it transforms the entire screen into an OLED pitch-black studio rack with real-time telemetry:
  * **Signal Path Verification**: Detects if your chain is **BIT-PERFECT DIRECT**, running through a shared mixer (**SHARED**), or in exclusive mode (**EXCLUSIVE WASAPI**).
  * **Resampler & DSP Alerts**: Highlights active DSP filters or audio engine sample rate changes (`RESAMPLED [in] -> [out]`).
* **Audio Upmixing (`A` / Shift+A)**:  
  Instantly toggles a **7.1 surround sound virtual upmix** via FFmpeg matrix routing.

---

### 5. Dedicated Image Viewer Mode
Opening still images (JPEG, PNG, WebP, AVIF, JXL, etc.) automatically triggers an optimized profile:
* Switches to **pure software decoding (`hwdec=no`)** for instantaneous, zero-latency opening.
* Bypasses heavy video filters and sets the scaler to **Mitchell-Netravali** to prevent oversharpening and ringing on high-resolution photography.
* Removes checkerboard tiles in favor of deep black borders (`#000000`).
* Infinite hold time without unexpected timeouts (`image-display-duration=inf`).

---

### 6. Built-in WebM & Clip Creator (`webm.lua`)
Press **`W` (Shift + W)** on any playing media to trigger an on-screen encoding and clipping toolkit:
* **Visual Crop Area (`c`)**: Set crop points A and B interactively with mouse coordinates.
* **In/Out Trimming (`1` / `2`)**: Define exact start/end points with preview jumping (`!`, `@`).
* **Encode Options Menu (`o`)**:
  * Formats: WebM (VP8/VP9), MP4 (x264, NVENC, AV1, HEVC), GIF (with Bayer/Sierra dither), MP3, or Raw AVI.
  * Automatic 2-pass encoding with automatic VP8 logfile patching.
  * Full control over target size (kB), CRF, bitrate constraints, FPS, and scale heights.
* **Live Loop Preview (`p`)** & **Interactive Progress Indicator (`e`)**.

---

## ⌨️ Keybindings Quick Reference

### Scalers, AI & Video Filters
| Key | Action |
| :---: | :--- |
| `1` | Toggle **NVIDIA RTX Video Super Resolution (VSR)** |
| `2` | Activate **NVIDIA Image Scaling (NIS)** |
| `3` | Activate **AMD FSR 1.0 (EASU + RCAS)** |
| `4` | Activate **Qualcomm SGSR v1** |
| `5` | Activate **AMD CAS (Scaled)** |
| `h` | Toggle **NVIDIA RTX Video True HDR** (SDR -> HDR) |
| `9` | Cycle base luma scaler between `nearest` and `lanczos` |
| `0` | **Reset**: Clear active shaders/VSR and restore default Lanczos |
| `-` | Show active GLSL shaders on OSD |
| `d` | Toggle **Debanding** |

### Audio & Studio HUD
| Key | Action |
| :---: | :--- |
| `a` | Toggle **Audiophile Studio HUD** on/off |
| `A` *(Shift+A)* | Toggle **7.1 Surround Upmixer** |

### Window, Playback & Navigation
| Key / Input | Action |
| :---: | :--- |
| `W` *(Shift+W)* | Launch the **WebM / Clip Maker** toolkit |
| `F11` | Toggle Fullscreen |
| `r` | Rotate video 90° clockwise |
| `l` | Toggle file loop (`inf` / `no`) |
| `Scroll Up` | Video Zoom In (`+0.08`) |
| `Scroll Down` | Video Zoom Out (`-0.08`) |
| `Middle Click` | Reset Zoom and Pan to center |
| `Right Click` | Play / Pause |
| `CTRL + Right` | Next playlist entry |
| `CTRL + Left` | Previous playlist entry |
| `q` / `ESC` | Quit MPV |

---

## 🛠️ Requirements & Installation

1. **MPV**: A modern build compiled for Windows (recommended: **v0.37+** or recent Git builds from shinchiro / zhongfly).
2. **NVIDIA GPU (Optional, recommended for AI features)**:
   * GeForce RTX 2000-series or newer.
   * NVIDIA Game Ready / Studio Drivers **>= 530.xx** (for RTX VSR) and **>= 551.xx** (for RTX True HDR).
   * Enable "RTX Video Enhancement" inside the *NVIDIA Control Panel* -> *Adjust video image settings*.
3. **Installation Steps**:
   * Clone or download this repository.
   * Copy the contents of the `mpv/` directory into your MPV configuration folder:
     ```text
     %APPDATA%\mpv\
     ```
     *(or into your `portable_config/` folder if you use a portable mpv installation)*.

---

## 📜 Credits & Acknowledgments

* MPV GLSL shader ports: **agyild** (*CAS, FSR, NIS, SGSR*).
* Architected, assembled, and refined by **[askasys-code](https://github.com/askasys-code)** — powered by Vibe Coding and Feels.

## 📂 Directory Layout

```text
mpv/
├── mpv.conf                        # Main configuration (gpu-next, d3d11 flip, cache, subtitles)
├── input.conf                      # Keybindings, shader triggers, and script messages
├── fonts.conf                      # System fontconfig configuration
├── configs/
│   └── mpv_file_extensions.conf    # Conditional profiles for [VIDEO], [AUDIO], and [IMAGE]
├── scalers/
│   ├── CAS-scaled.glsl             # AMD FidelityFX CAS v1.0.2
│   ├── FSR.glsl                    # AMD FidelityFX Super Resolution v1.0.2
│   ├── NVScaler.glsl               # NVIDIA Image Scaling v1.0.2 (Compute Shader)
│   └── SGSR.glsl                   # Qualcomm Snapdragon GSR v1
└── scripts/
    ├── audio-player.lua            # Audiophile HUD & Signal Path Monitor
    ├── autohdr.lua                 # Smart RTX Video True HDR Controller
    ├── autovsr.lua                 # Dynamic Resolution RTX VSR Auto-Scaler
    └── webm.lua                    # Integrated WebM / MP4 / GIF Clip Maker

---
