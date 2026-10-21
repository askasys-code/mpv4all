-- =========================================================================
-- NVIDIA RTX Video Super Resolution (VSR) Auto-Scaler for MPV
-- Optimized for Direct3D 11 Video Processor (d3d11vpp)
-- =========================================================================

local vsr_enabled = false
local vsr_label = "@vsr"

-- Determine active viewport resolution (Fullscreen display vs Windowed size)
local function get_target_resolution()
    local is_fullscreen = mp.get_property_bool("fullscreen", false)
    if is_fullscreen then
        local dw = mp.get_property_native("display-width")
        local dh = mp.get_property_native("display-height")
        if dw and dh and dw > 0 and dh > 0 then
            return dw, dh
        end
    end

    -- Windowed mode: retrieve current window/OSD frame size
    local ww, wh = mp.get_osd_size()
    if ww and wh and ww > 0 and wh > 0 then
        return ww, wh
    end

    return mp.get_property_native("display-width"), mp.get_property_native("display-height")
end

-- Safely remove existing VSR filter
local function remove_vsr_filter()
    local vf_str = mp.get_property("vf") or ""
    if string.match(vf_str, vsr_label) then
        mp.commandv("vf", "remove", vsr_label)
    end
end

-- Check if pixel format is compatible with RTX VSR hardware
local function is_format_supported(pixfmt)
    if not pixfmt then return false end
    local valid_formats = {
        ["nv12"]   = true,
        ["yuv420p"] = true,
        ["p010"]   = true,
        ["p010le"] = true
    }
    return valid_formats[pixfmt] or false
end

local function toggle_vsr()
    local video_w = mp.get_property_native("width")
    local video_h = mp.get_property_native("height")
    local target_w, target_h = get_target_resolution()

    if not (video_w and video_h and target_w and target_h) then
        mp.osd_message("VSR: Video or display dimensions unavailable", 2)
        return
    end

    local pixfmt = mp.get_property_native("video-params/hw-pixelformat")
                or mp.get_property_native("video-params/pixelformat")

    -- Remove any active VSR instance
    remove_vsr_filter()

    if vsr_enabled then
        vsr_enabled = false
        mp.osd_message(string.format("NVIDIA VSR: OFF (Native: %dx%d)", video_w, video_h), 2)
        return
    end

    -- Format validation (including 10-bit P010 HDR)
    if not is_format_supported(pixfmt) then
        mp.osd_message(string.format("NVIDIA VSR: Unsupported format (%s)", tostring(pixfmt)), 2)
        return
    end

    -- Calculate aspect-ratio preserving scale factor
    local scale_x = target_w / video_w
    local scale_y = target_h / video_h
    local scale = math.min(scale_x, scale_y)

    -- If video already matches or exceeds viewport, upscaling is redundant
    if scale <= 1.05 then
        mp.osd_message(string.format("NVIDIA VSR: Not needed (Video: %dx%d >= Target)", video_w, video_h), 2)
        return
    end

    -- Clamp to NVIDIA hardware limit (1.0x to 4.0x) and round to 1 decimal place
    scale = math.min(scale, 4.0)
    scale = math.floor(scale * 10 + 0.5) / 10

    -- Append filter using labeled instance
    local filter_cmd = string.format("%s:d3d11vpp:scaling-mode=nvidia:scale=%.1f", vsr_label, scale)
    mp.commandv("vf", "append", filter_cmd)

    vsr_enabled = true
    local out_w = math.floor(video_w * scale)
    local out_h = math.floor(video_h * scale)
    mp.osd_message(string.format("NVIDIA RTX VSR: Active (%.1fx -> %dx%d)", scale, out_w, out_h), 2)
end

-- Automatically reset state on file transition
local function on_file_loaded()
    vsr_enabled = false
end

mp.register_event("file-loaded", on_file_loaded)
mp.register_script_message("autovsr-toggle", toggle_vsr)