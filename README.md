# ⚡ mpv4all

# MPV Master Configuration: Videophile, Studio Audio & High-Res Image Suite

An elite, highly optimized configuration suite for [mpv](https://mpv.io) tailored for modern Windows 11 / Direct3D 11 environments, NVIDIA RTX hardware, high-refresh OLED displays, audiophile headphone listening, and high-resolution photo viewing.

---

## Key Highlights & Architectural Features

### 1. Cinema Frame Pacing (24 fps on 60 Hz – 240 Hz Displays)
* **Zero Judder / Zero Dropped Frames**: Utilizes `video-sync=display-resample` to slave video presentation directly to the physical display VBlank, micro-adjusting audio clock by $\pm0.1\%$.
* **`tscale=oversample`**: Eliminates 3:2 pulldown judder across 60 Hz, 120 Hz, 144 Hz, 165 Hz, and 240 Hz panels without introducing artificial frame interpolation ("soap opera effect") or motion blur.
* **On-the-Fly Pacing Switch (`Shift + M`)**: Instant hotkey toggle between `display-resample` (best for fixed refresh rates) and `audio` clock (mandatory for G-Sync / FreeSync VRR).

### 2. Video Pipeline & Rendering (`vo=gpu-next`)
* **Direct3D 11 Flip Model**: `gpu-api=d3d11` paired with `d3d11-flip=yes` and native zero-copy `hwdec=d3d11va`.
* **True OLED Blacks & Windows 11 HDR**: `target-colorspace-hint=yes` and `d3d11-output-csp=auto` ensure direct pass-through to the Windows Advanced Color swapchain, bypassing SDR double-tone-mapping.
* **Modern libplacebo Clamping**: Ringing suppression via `scale-clamp=yes` and `cscale-clamp=yes`.
* **Compute Dithering**: 16-pass `dither=error-diffusion` (`sierra-lite`) for banding-free dark gradients.

### 3. Hardware AI & Neural Upscaling Suite
* Direct one-key access to hardware AI tensor scalers and spatial GLSL algorithms:
  * **1**: NVIDIA RTX Video Super Resolution (Hardware VSR via `d3d11vpp`).
  * **2**: NVIDIA Image Scaling (NIS Spatial Upscaler).
  * **3**: AMD FidelityFX Super Resolution (FSR 1.0: EASU + RCAS).
  * **4**: Qualcomm Snapdragon Game Super Resolution (SGSR).
  * **5**: AMD Contrast Adaptive Sharpening (CAS Scaled Reconstruction).
  * **h**: NVIDIA RTX Video True HDR (Automated SDR $\rightarrow$ HDR tone-mapping).

### 4. Integrated Audiophile HUD & Curated Headphone DSP
* **Dual-Mode Studio HUD (`a`)**:
  * *Floating Capsule*: Compact metadata and stream technicals for video playback and music with embedded artwork.
  * *Studio Audio Rack*: Full-screen mastering display for pure audio playback (sample rate, bit depth, container, audio-device output, signal path).
* **5-Stage Headphone DSP Suite (`Shift + A`)**:
  Integrated directly inside `audio-player.lua` with clean, human-readable OSD notices:
  1. **Windows Sonic 7.1 Spatial Upmix**: Expands 2.0 stereo into an 8-channel virtual soundstage, waking up Windows Sonic's 3D binaural room HRTF engine.
  2. **BS2B Studio Crossfeed**: Bauer stereophonic-to-binaural algorithm simulating nearfield studio monitors to eliminate headphone ear fatigue.
  3. **Stereo Soundstage Expander**: Widens horizontal acoustic stage while maintaining bit-perfect 2.0 channel architecture.
  4. **Dialogue Boost & Night Mode**: Real-time dynamic audio normalization (`dynaudnorm`) lifting quiet dialogue while compressing loud explosions.
  5. **Direct / Bit-Perfect (OFF)**: Pure, uncolored passthrough for audiophile listening.

### 5. High-Performance Photo & Graphic Viewer
* **Zero-Lag Zoom**: Fast `dither=fruit`, `correct-downscaling=no`, and `sigmoid-upscaling=no` active exclusively during image viewing for instant 144/240 Hz viewport response.
* **Viewport Navigation**: Snappy zoom (`WHEEL`), 2D viewport panning (`Alt + Arrows`), one-click reset (`MBTN_MID` / `Backspace`), and folder navigation (`PGUP` / `PGDWN`).
* **Non-Destructive Profiles**: Utilizes `profile-restore=copy` to prevent image viewer settings (`hwdec=no`, scalers) from corrupting subsequent video files in the playlist.

### 6. Modern NVENC Hardware Clipper (`Shift + W`)
* Integrated toolkit for on-the-fly video clipping, trimming, cropping, and encoding via NVENC (H.264, HEVC, AV1) or high-quality palette-generated GIFs.

---

## Keybindings Cheat Sheet

### Scalers & Video Enhancements
| Key | Action | Description |
| :--- | :--- | :--- |
| `1` | `autovsr-toggle` | Toggle NVIDIA RTX Video Super Resolution (AI Tensor) |
| `2` | NIS | Enable NVIDIA Image Scaling GLSL |
| `3` | AMD FSR | Enable AMD FidelityFX Super Resolution (EASU + RCAS) |
| `4` | Qualcomm SGSR | Enable Snapdragon Game Super Resolution |
| `5` | AMD CAS | Enable AMD Contrast Adaptive Sharpening |
| `h` | `autohdr-toggle` | Toggle NVIDIA RTX Video True HDR (SDR $\rightarrow$ HDR) |
| `9` | Cycle Scaler | Switch base luma fallback between `lanczos` and `nearest` |
| `d` | `cycle deband` | Toggle debanding algorithm |
| `0` | **Master Reset** | Clears all shaders, VSR, True HDR, DSP filters, zoom, and restores default pacing |
| `-` | Query Status | Display active GLSL shaders and current sync mode on OSD |

### Display & Motion Synchronization
| Key | Action | Description |
| :--- | :--- | :--- |
| `Shift + M` | Toggle Pacing | Cycle between `display-resample` (Fixed 60–240Hz) and `audio` (G-Sync/VRR) |

### Audio & Headphone DSP
| Key | Action | Description |
| :--- | :--- | :--- |
| `a` | Toggle Audio HUD | Show/hide the floating capsule or studio mastering rack |
| `Shift + A` | **Cycle Audio DSP** | Cycle: 7.1 Spatial Upmix $\rightarrow$ BS2B Crossfeed $\rightarrow$ Stereo Expander $\rightarrow$ Night Mode $\rightarrow$ Direct |
| `Alt + A` | Audio Channels | Toggle output container between `auto-safe` and forced `7.1` |
| `UP` / `DOWN` | Volume $\pm2$ | Adjust volume by 2% increments |
| `m` | `cycle mute` | Toggle master mute |

### Image Viewer & Viewport Navigation
| Key | Action | Description |
| :--- | :--- | :--- |
| `WHEEL_UP` | Zoom In | Responsive 0.10 scale zoom |
| `WHEEL_DOWN` | Zoom Out | Responsive 0.10 scale unzoom |
| `MBTN_MID` / `Backspace` | Reset Geometry | Re-center image and reset zoom to 100% |
| `Alt + Arrows` | Pan Viewport | Move around zoomed-in photos or videos |
| `PGUP` / `PGDWN` | Browse Folder | Previous / Next image or file in folder |
| `r` / `Shift + R` | Rotate | Rotate image 90° clockwise / 270° counter-clockwise |
| `Alt + V` | Mirror Flip | Flip image horizontally |

### Playback & Tools
| Key | Action | Description |
| :--- | :--- | :--- |
| `SPACE` / `MBTN_RIGHT` | Pause / Play | Toggle playback pause |
| `LEFT` / `RIGHT` | Seek $\pm5$s | Exact 5-second jump |
| `Shift + LEFT/RIGHT` | Seek $\pm1$s | Precise 1-second frame step |
| `.` / `,` | Frame Step | Advance / rewind single frame |
| `f` / `F11` | Fullscreen | Toggle fullscreen mode |
| `TAB` / `Shift + I` | Stats Display | Toggle detailed real-time render/performance stats |
| `Shift + W` | Clip Maker | Open hardware video trimmer and encoder |
| `s` / `Shift + S` | Screenshot | Capture screenshot with / without subtitles |
| `q` / `ESC` | Quit | Exit player |

---

## Technical Details

### Fixed Refresh Rate vs. G-Sync / VRR
* **Fixed Refresh Monitors (60 Hz, 120 Hz, 144 Hz, 240 Hz)**: Keep `display-resample` active (default). mpv eliminates 3:2 pulldown judder via `interpolation=yes` + `tscale=oversample`, maintaining 100% film timing consistency.
* **G-Sync / FreeSync (VRR Active)**: Press **`Shift + M`** to switch to `audio` clock. This prevents mpv's display resampler from fighting the GPU variable refresh rate controller.

### Windows Sonic & The 7.1 Spatial Upmixer
Standard stereo tracks (2.0) bypass Windows Sonic's 3D room engine by default. Selecting **`Audio DSP: Windows Sonic 7.1 Spatial Upmix`** (`Shift + A`) synthesizes an 8-channel matrix container, triggering Windows Sonic's HRTF engine to position virtual speakers in a 360° soundstage around your headphones. When listening to pure stereo music, cycle to **`Direct / Bit-Perfect (OFF)`** for unadulterated source reproduction.

---

## Requirements & Installation
1. Install a modern 64-bit build of [mpv](https://sourceforge.net/projects/mpv-player-windows/files/) (v0.38+ recommended, built with `libplacebo` and `d3d11vpp`).
2. Clone or copy these configuration folders into your mpv directory:
   * Windows Portable: `<mpv-dir>/portable_config/`
   * Windows Standard: `%APPDATA%/mpv/`
3. Ensure your GPU drivers are up-to-date (NVIDIA Driver 530+ required for RTX VSR and True HDR).
