# 🎛️ MPV-RTX  (NVIDIA Dark Glass Edition)

[![Engine](https://img.shields.io/badge/MPV-gpu--next-00E676?style=for-the-badge&logo=mpv&logoColor=white)](https://mpv.io)
[![AI Upscaling](https://img.shields.io/badge/RTX_Video-VSR_%7C_True_HDR-76B900?style=for-the-badge&logo=nvidia&logoColor=white)](https://nvidia.com)
[![Aesthetics](https://img.shields.io/badge/Design-NVIDIA_Dark_Glass-0A0A0A?style=for-the-badge&logo=materialdesign&logoColor=00E676)](#-the-nvidia-dark-glass-aesthetic)

An ultra-refined, videophile-grade media environment engineered for Direct3D 11 and NVIDIA RTX architectures. Built on `vo=gpu-next`, this suite delivers zero-copy hardware acceleration, frame-perfect pacing for high-refresh displays, tensor-core AI upscaling, studio-grade multichannel audio monitoring, and an exclusive vector-rendered glassmorphism user interface.

---

## 💎 The NVIDIA Dark Glass Aesthetic

Unlike standard media players with generic flat controls, this suite features a bespoke, unified design system rendered entirely via real-time vector ASS overlays:

* **Obsidian Glass Containers (`#0A0A0A` @ ~80% Opacity)**: Clean, translucent frosted backdrop cards that maintain readability over high-contrast video without obscuring content.
* **Signature NVIDIA Green Accents (`#00E676`)**: Precision top accent borders, tactical progress indicators, and custom vector diamond badges (`◆`) for section hierarchy.
* **RivaTuner Telemetry Cyan (`#00E5FF`)**: High-contrast, fatigue-free readouts for clocks, codecs, timestamps, and demuxer cache buffers.
* **OLED Black Optimization**: Borderless pure black letterboxing (`#000000`) designed to turn off self-lit OLED pixels entirely.
* **Dynamic DPI Vector Scaling**: Every font glyph, vector border, button hitbox, and layout coordinate scales responsively across 1080p, 1440p, 4K UHD, and ultra-wide displays.

---

## ⚡ Core Engine & Video Architecture

* **Modern Direct3D 11 Presentation**: Utilizes `vo=gpu-next` paired with native DXGI Flip presentation model (`d3d11-flip=yes`) and automatic swapchain color space detection for seamless SDR/HDR switching.
* **Hardware Decoding**: Zero-copy `d3d11va` hardware decoding across all modern formats (AV1 10-bit, HEVC, H.264, VP9).
* **Judder-Free Motion Pacing**: Audio-resampling display synchronization (`video-sync=display-resample` with `tscale=oversample`) eliminates 3:2 pulldown judder, providing cinematic motion smoothness on 60Hz through 240Hz+ VRR displays.
* **Advanced Color Reconstruction**: High-order Bicubic and Lanczos scaling filters with tuned anti-ringing thresholds for authentic film grain and edge reproduction.

---

## 🚀 Neural Shaders & AI Upscaling Pipeline

Switch seamlessly between hardware AI tensor upscalers and spatial reconstruction shaders on the fly:

| Hotkey | Upscaler Engine | Processing Tier | Description |
| :---: | :--- | :--- | :--- |
| **`1`** | **NVIDIA RTX VSR** | Hardware Tensor AI | Deep-learning super resolution up to 4.0x via D3D11 video post-processing. |
| **`2`** | **NVIDIA NIS** | Spatial Compute Shader | Direction-adaptive sharpening and linear upscaling engine. |
| **`3`** | **AMD FSR 1.0** | Spatial Two-Pass Shader | Edge-Adaptive Super Sampling (EASU) + Robust Contrast-Adaptive Sharpening (RCAS). |
| **`4`** | **Qualcomm SGSR** | Single-Pass Edge Shader | Direction-aware Lanczos reconstruction tuned for minimal power draw. |
| **`5`** | **AMD CAS (Scaled)** | Contrast Reconstruction | Adaptive high-frequency luminance sharpening in linear light. |
| **`h`** | **NVIDIA RTX True HDR** | Tensor Core Inverse Tone | Real-time SDR to HDR10 (PQ) conversion with native HDR override protection. |
| **`0`** | **Master Reset** | Clean Fallback | Clears all active neural shaders, VSR, and HDR overrides back to clean native rendering. |

---

## 📊 The Diagnostic HUD Suite

### 1. NVIDIA Hardware Monitor (`g`)
Direct real-time hardware telemetry polled via non-blocking asynchronous calls:
* **GPU Metrics**: Core clock, memory clock, GPU load, and dedicated NVDEC hardware decoder engine utilization.
* **Thermal & Power**: Die temperature with dynamic thermal alerts, fan tachometers (including Fan Stop mode), real-time board power draw against TDP limits.
* **VRAM Telemetry**: MiB-accurate VRAM utilization and total physical frame buffer capacity.
* **Display Engine**: Physical display refresh rate, container framerate, dropped/mistimed frame counters, render latency in milliseconds, and OS Variable Refresh Rate (G-Sync) status.

### 2. Video Diagnostics Monitor (`i` / `I`)
Deep container, stream, and color science diagnostics:
* Container metadata, physical file size, live demuxer cache duration, and RAM buffer occupancy.
* Source video format, active hardware decoder, exact aspect ratio (SAR/DAR), and real-time scaling resolution indicators (e.g. `1080p -> 4K`).
* Color science tracking: bit-depth, pixel format, active color primaries (`BT.709` vs `BT.2020 WCG`), and gamma transfer curves (`BT.1886`, `sRGB`, `HDR10 PQ`, `HLG`).

### 3. Studio Audio Monitor (`a`)
Audiophile and multichannel acoustic telemetry suite:
* **Dynamic 7.1 Speaker Matrix**: Real-time physical channel activity grid (`FL`, `FR`, `C`, `LFE`, `SL`, `SR`, `BL`, `BR`).
* **Hardware Acoustic Parameters**: Bit-perfect sample rates (e.g. `48.000 Hz`), audio bit-depth (`16-bit`, `24-bit`, `32-bit Float`), and real-time audio bitrates.
* **A/V Sync Offset**: Millisecond-accurate audio/video synchronization drift tracking.
* **Headphone DSP Suite (`A`)**: One-key cycle through 7.1 Spatial Upmixer, Bauer BS2B Binaural Crossfeed, Stereo Soundstage Widener, and Dynamic Night Mode.
* **Zero-Clipping Bass Boost (`b`)**: Audiophile low-end equalizers with negative pre-attenuation headroom (`Warmth +4dB`, `Punch +7dB`, `Sub-Bass +10dB`).
* **Channel Soloing (`B` / `Ctrl+1-5`)**: Isolate dialogue (Center), music score (Front L/R), surround effects, rear backs, or LFE subwoofer independently.

---

## 🎮 Modern Bottom Bar (OSC)

A completely standalone, zero-lag on-screen controller engineered to replace mpv's default interface:

* **Decoupled 60 FPS Render Loop**: Scrubbing and mouse tracking are fully decoupled from mpv's core event queue, eliminating drag latency, rubber-banding, or stuck sliders.
* **RAM Cache Buffer Line**: Visual cyan buffer gauge displaying demuxer cache readahead in real time.
* **Interactive Chapter Marks**: Subtle tick marks across the timeline with floating chapter title tooltips on hover.
* **Dynamic Track Badges**: Bottom buttons adapt in real time to show the exact active channels (`[Stereo 2.0]`, `[5.1]`, `[7.1]`) and languages (`[ITA • 5.1]`).
* **Multi-Audio & Multi-Subtitle Popups**: Clicking on the audio or subtitle badge opens a floating glass menu detailing codecs, channel setups, and language options.
* **Clickable Volume Slider**: Left-click on the volume badge to toggle instant Mute, scroll with the mouse wheel, or click/drag directly on the dedicated volume bar to set levels from 0% to 100%.
* **Guaranteed Auto-Hide**: Fades out cleanly after 2 seconds of mouse inactivity, even if the cursor is resting over the bar.

---

## 🎬 Hardware Clip Maker (`W`)

A built-in video editor and converter powered by hardware NVENC:

* **Lossless Precision Trimming**: Set frame-accurate Start (`1`) and End (`2`) markers with instant jump controls.
* **Interactive Crop Selector (`c`)**: Dimmed viewport mask with mouse-driven cropping. All coordinates automatically snap to even dimensions to guarantee codec compliance.
* **Hardware Exporters**: Export directly to NVENC AV1 (RTX 40-series), NVENC HEVC, NVENC H.264, VP9, CPU x264/x265, Palette-Generated High-Framerate GIF, or MP3.
* **Asynchronous Encoding**: Subprocess encoding runs entirely in the background without freezing video playback.
* **Smart UI Coordination**: Automatically silences the bottom controller while active, docking cleanly at the bottom-left beneath the video diagnostics monitor.

---

## ⌨️ Master Keybindings Cheat Sheet

### Scaling, Shaders & Display
| Key | Action |
| :--- | :--- |
| `1` | Toggle NVIDIA RTX Video Super Resolution (VSR) |
| `2` | Set NVIDIA Image Scaling (NIS) |
| `3` | Set AMD FidelityFX Super Resolution (FSR 1.0) |
| `4` | Set Qualcomm Snapdragon Game Super Resolution (SGSR) |
| `5` | Set AMD Contrast Adaptive Sharpening (CAS) |
| `h` | Toggle NVIDIA RTX Video True HDR (SDR ➔ HDR) |
| `d` | Toggle Debanding Filter |
| `M` | Cycle Motion Sync (`display-resample` vs `audio` VRR clock) |
| `0` | Master Reset (Clears shaders, VSR, HDR, audio DSP, and pans) |

### Telemetry & Overlays
| Key | Action |
| :--- | :--- |
| `TAB` | Synchronized Master Toggle (Opens/Closes HUDs together) |
| `i` / `I` | Toggle Video & Container Diagnostics Monitor |
| `g` | Toggle NVIDIA Hardware & GPU Telemetry Monitor |
| `a` | Toggle Studio Audio Suite & Speaker Matrix |

### Audio DSP, Equalizers & Soloing
| Key | Action |
| :--- | :--- |
| `A` | Cycle Headphone DSP (Spatial Upmix ➔ BS2B ➔ Widener ➔ Nightmode ➔ Direct) |
| `b` | Cycle Zero-Clipping Bass Boost (Off ➔ +4dB ➔ +7dB ➔ +10dB) |
| `B` | Cycle Channel Solo (All ➔ Center ➔ Front ➔ Surrounds ➔ Rear ➔ LFE) |
| `Ctrl+0` | Restore All Audio Channels |
| `Ctrl+1` | Solo Front L/R Channels |
| `Ctrl+2` | Solo Center Channel (Dialogue Isolation) |
| `Ctrl+3` | Solo Surround Channels |
| `Ctrl+4` | Solo Rear Back Channels |
| `Ctrl+5` | Solo Subwoofer / LFE Channel |

### Navigation, Image Viewing & Tools
| Key | Action |
| :--- | :--- |
| `W` | Open Hardware Clip Maker |
| `WHEEL_UP` / `DOWN` | Zoom In / Zoom Out (Smooth 0.10 steps) |
| `MBTN_MID` / `BS` | Reset Zoom & Center Pan |
| `Alt+Arrows` | Pan Viewport across zoomed videos / high-res photos |
| `r` / `R` | Rotate 90° Clockwise / Counter-Clockwise |
| `Alt+v` | Mirror Flip Horizontally |
| `s` / `S` | Capture Screenshot / Clean Screenshot (Without Subtitles) |

---

## 📋 Compatibility

* **OS**: Windows 10 / 11 (64-bit)
* **Graphics**: NVIDIA GeForce GTX 900-series through RTX 40/50-series (RTX required for Tensor VSR & True HDR)
* **Display**: Standard SDR Displays, Windows Advanced Color (WAC), HDR10 Displays, High-Refresh Gaming Monitors (60Hz – 360Hz+ G-Sync/VRR)
* **Core Player**: MPV v0.38+ compiled with `libplacebo` and Direct3D 11 support
