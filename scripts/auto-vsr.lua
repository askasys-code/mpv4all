-- =========================================================================
-- NVIDIA RTX Video Super Resolution (VSR) Auto-Scaler for MPV
-- Dynamic Viewport-Targeting & Aspect-Ratio Preserving Engine
-- Fully Synchronized & Stateless Filter Controller
-- =========================================================================

local vsr_label = "@vsr"

-- Inspect the active filter chain to determine if VSR is currently engaged
local function is_vsr_active()
    local vf_str = mp.get_property("vf") or ""
    return vf_str:find(vsr_label, 1, true) ~= nil
end

-- Safely remove existing VSR filter instance
local function remove_vsr_filter()
    if is_vsr_active() then
        mp.commandv("vf", "remove", vsr_label)
    end
end

-- Determine active viewport resolution (Fullscreen display vs Windowed inner video area)
local function get_target_resolution()
    local is_fullscreen = mp.get_property_bool("fullscreen", false)
    if is_fullscreen then
        local dw = mp.get_property_native("display-width")
        local dh = mp.get_property_native("display-height")
        if dw and dh and dw > 0 and dh > 0 then
            return dw, dh
        end
    end

    -- Windowed mode: retrieve inner video viewport excluding letterbox/pillarbox margins
    local dims = mp.get_property_native("osd-dimensions")
    if dims and dims.w and dims.w > 0 and dims.h and dims.h > 0 then
        local vid_w = dims.w - (dims.ml or 0) - (dims.mr or 0)
        local vid_h = dims.h - (dims.mt or 0) - (dims.mb or 0)
        if vid_w > 0 and vid_h > 0 then
            return vid_w, vid_h
        end
        return dims.w, dims.h
    end

    local ww, wh = mp.get_osd_size()
    if ww and wh and ww > 0 and wh > 0 then
        return ww, wh
    end

    return mp.get_property_native("display-width"), mp.get_property_native("display-height")
end

-- Check if pixel format is compatible with RTX VSR hardware (8-bit and 10-bit YUV 4:2:0)
local function is_format_supported(pixfmt)
    if not pixfmt then return false end
    local clean_fmt = tostring(pixfmt):lower():match("^%s*(.-)%s*$")
    local valid_formats = {
        ["nv12"]        = true,
        ["yuv420p"]     = true,
        ["p010"]        = true,
        ["p010le"]      = true,
        ["yuv420p10le"] = true,
    }
    return valid_formats[clean_fmt] or false
end

-- Main toggle and scale calculation engine
local function toggle_vsr(silent_rescale)
    -- Guard: Prevent running on still images or pure audio album art
    local vtrack = mp.get_property_native("current-tracks/video")
    if not vtrack or vtrack.image or vtrack.albumart then
        if not silent_rescale then
            mp.osd_message("NVIDIA VSR: Not applicable for static images or audio", 2)
        end
        return
    end

    local raw_w = mp.get_property_native("width")
    local raw_h = mp.get_property_native("height")
    local video_w = mp.get_property_native("dwidth") or raw_w
    local video_h = mp.get_property_native("dheight") or raw_h

    -- 1. If VSR filter is currently active and not an auto-rescale update, turn it OFF
    if is_vsr_active() and not silent_rescale then
        remove_vsr_filter()
        mp.osd_message(string.format("NVIDIA VSR: OFF (Native: %dx%d)", raw_w or 0, raw_h or 0), 2)
        return
    end

    -- 2. Validate input and display dimensions
    local target_w, target_h = get_target_resolution()
    if not (video_w and video_h and target_w and target_h and video_w > 0 and video_h > 0) then
        if not silent_rescale then
            mp.osd_message("NVIDIA VSR: Video or display dimensions unavailable", 2)
        end
        return
    end

    -- 3. Validate hardware-accelerated pixel format
    local pixfmt = mp.get_property_native("video-params/hw-pixelformat")
                or mp.get_property_native("video-params/pixelformat")

    if not is_format_supported(pixfmt) then
        if not silent_rescale then
            mp.osd_message(string.format("NVIDIA VSR: Unsupported format (%s)", tostring(pixfmt)), 2)
        end
        return
    end

    -- 4. Calculate aspect-ratio preserving isotropic scale factor
    local scale_x = target_w / video_w
    local scale_y = target_h / video_h
    local scale = math.min(scale_x, scale_y)

    -- Video already matches or exceeds target resolution: upscaling redundant
    if scale <= 1.01 then
        if is_vsr_active() then
            remove_vsr_filter()
        end
        if not silent_rescale then
            mp.osd_message(string.format("NVIDIA VSR: Not needed (Video: %dx%d >= Target: %dx%d)", video_w, video_h, target_w, target_h), 2.5)
        end
        return
    end

    -- Clamp to NVIDIA RTX hardware boundary (1.0x to 4.0x) and round to 2 decimals
    scale = math.min(scale, 4.0)
    scale = math.floor(scale * 100 + 0.5) / 100

    -- Remove any existing instance before appending
    remove_vsr_filter()

    -- 5. Append filter with labeled instance
    local filter_cmd = string.format("%s:d3d11vpp=scaling-mode=nvidia:scale=%.2f", vsr_label, scale)
    mp.commandv("vf", "append", filter_cmd)

    local out_w = math.floor((raw_w or video_w) * scale)
    local out_h = math.floor((raw_h or video_h) * scale)
    local msg_prefix = silent_rescale and "NVIDIA RTX VSR: Rescaled" or "NVIDIA RTX VSR: Active"
    mp.osd_message(string.format("%s (%.2fx -> %dx%d)", msg_prefix, scale, out_w, out_h), 2)
end

-- Dynamically update scaling factor if fullscreen mode changes while VSR is active
local function on_fullscreen_change(_, is_fs)
    if is_fs ~= nil and is_vsr_active() then
        mp.add_timeout(0.1, function()
            toggle_vsr(true)
        end)
    end
end

-- Automatically clean filter when loading a new file
local function on_file_loaded()
    remove_vsr_filter()
end

mp.register_event("file-loaded", on_file_loaded)
mp.observe_property("fullscreen", "bool", on_fullscreen_change)

-- Script Message API Handlers
mp.register_script_message("autovsr-toggle", function() toggle_vsr(false) end)
mp.register_script_message("autovsr-update", function() toggle_vsr(true) end)
mp.register_script_message("autovsr-disable", remove_vsr_filter)