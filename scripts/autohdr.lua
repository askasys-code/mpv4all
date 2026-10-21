-- =========================================================================
-- NVIDIA RTX Video True HDR Controller for MPV
-- Prevents double tone-mapping on native HDR and handles SDR-to-HDR cleanly
-- =========================================================================

local hdr_enabled = false
local hdr_label = "@truehdr"

-- Inspect video metadata to determine if content is already native HDR
local function is_native_hdr()
    local gamma = mp.get_property("video-params/gamma") or ""
    local colormatrix = mp.get_property("video-params/colormatrix") or ""
    local sig_peak = mp.get_property_number("video-params/sig-peak", 1.0)

    -- Detect PQ (HDR10/Dolby Vision), HLG, or BT.2020 Wide Color Gamut with high peak
    if gamma == "pq" or gamma == "hlg" or colormatrix == "bt.2020-ncl" or sig_peak > 1.0 then
        return true
    end
    return false
end

-- Safely remove existing True HDR filter
local function remove_hdr_filter()
    local vf_str = mp.get_property("vf") or ""
    if string.match(vf_str, hdr_label) then
        mp.commandv("vf", "remove", hdr_label)
    end
end

local function toggle_hdr()
    local video_w = mp.get_property_native("width")
    if not video_w then
        mp.osd_message("True HDR: No video loaded", 2)
        return
    end

    remove_hdr_filter()

    if hdr_enabled then
        hdr_enabled = false
        mp.osd_message("NVIDIA True HDR: OFF", 2)
        return
    end

    -- Abort if the video already contains native HDR mastering
    if is_native_hdr() then
        mp.osd_message("NVIDIA True HDR: Skipped (Content is already native HDR)", 3)
        return
    end

    -- Append filter using isolated instance label
    local filter_cmd = string.format("%s:d3d11vpp:nvidia-true-hdr", hdr_label)
    mp.commandv("vf", "append", filter_cmd)

    hdr_enabled = true
    mp.osd_message("NVIDIA True HDR: Active (SDR -> HDR)", 2)
end

-- Reset toggle state when loading another file in the playlist
local function on_file_loaded()
    hdr_enabled = false
end

mp.register_event("file-loaded", on_file_loaded)
mp.register_script_message("autohdr-toggle", toggle_hdr)