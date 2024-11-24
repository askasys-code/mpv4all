# mpv4all v5.1
______________________________________________________

This is my personal mpv configuration for the best quality experience with NVIDIA GPU.

You can use this configuration to have an universal video, image and audio player with many convenient functions.
The main functions are the toggle keys for upscaling.

## Software Requirements
- mpv https://github.com/mpv-player/mpv | Download: https://github.com/zhongfly/mpv-winbuild/releases
- Windows OS (I haven't tested on Linux.)

## System Requirements
- Minimum: GTX 750 or equivalent for basic upcaling with NIS and FSR.
- Recommanded: RTX 30 or 40 series for RTX Video Upscaling.

# Keyboard Bindings:

### Video functions

- <kbd> 1 </kbd> - Upscale with NVIDIA Image Scaling (NIS)
- <kbd> 2 </kbd> - AI Upscale with RTX Video Super Resolution
- <kbd> 8 </kbd> - Nearest Neighbor scaling
- <kbd> 9 </kbd> - Upscale with AMD FidelityFX™ Super Resolution (FSR)
- <kbd> 0 </kbd> - Disable everything and return to the default values
- <kbd> CTRL+\ </kbd> - Display actual shaders
- <kbd> r </kbd> - Rotate video
- <kbd> D </kbd> - Activate deband
- <kbd> shift+c </kbd> - Auto crop function
- <kbd> shift+w </kbd> - Video Cutter function # instructions here: https://github.com/ekisu/mpv-webm
______________________________________________________

### Audio functions

- <kbd> b </kbd> - Bass booster
- <kbd> a </kbd> - Upmix audio from Stereo 2.0ch to Surround 7.1ch
- <kbd> Alt+a </kbd> - Downmix audio from Surround to Stereo 2.0ch
- <kbd> A </kbd> - Boost rear audio channels, just for fun.
- <kbd> CTRL+a </kbd> - Listen only rear channels, just for fun.
______________________________________________________

### Other controls

- <kbd> UP </kbd> <kbd> DOWN </kbd> - Pan & Scan function
- Mouse <kbd> WHEEL_UP </kbd> <kbd> WHEEL_DOWN </kbd> - Zoom-in and Zoom-out
- Mouse <kbd> LEFT_CLICK </kbd> - Click and hold to move the image after the zoom
- Mouse <kbd> RIGHT_CLICK </kbd> - Pause
- <kbd>CTRL+LEFT</kbd> Previous file
- <kbd>CTRL+RIGHT</kbd> Next file

______________________________________________________


All the shaders are property of their rightful owners. I have only edited mpv.conf, input.conf and some LUA scripts to fits better with my configuration.
