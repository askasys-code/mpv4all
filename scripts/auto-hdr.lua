-- =========================================================================
-- NVIDIA RTX Video True HDR Controller for MPV
-- Prevents double tone-mapping on native HDR and handles SDR-to-HDR cleanly
-- Fully Synchronized & Stateless Filter Controller
-- =========================================================================

local hdr_label = "@truehdr"

-- Inspect video filter pipeline to determine if True HDR is currently active
local function is_hdr_active()
    local vf_str = mp.get_property("vf") or ""
    return vf_str:find(hdr_label, 1, true) ~= nil
end

-- Safely remove existing True HDR filter instance
local function remove_hdr_filter()
    if is_hdr_active() then
        mp.commandv("vf", "remove", hdr_label)
    end
end

-- Inspect video metadata to determine if content is already native HDR
local function is_native_hdr()
    local gamma = tostring(mp.get_property("video-params/gamma") or ""):lower()
    local colormatrix = tostring(mp.get_property("video-params/colormatrix") or ""):lower()
    local primaries = tostring(mp.get_property("video-params/primaries") or ""):lower()
    local sig_peak = mp.get_property_number("video-params/sig-peak", 1.0)

    -- Detect PQ (HDR10 / Dolby Vision), HLG, or Wide Color Gamut with high luminance
    if gamma:find("pq") or gamma:find("smpte2084") or gamma:find("hlg") or gamma:find("arib") then
        return true
    end

    if colormatrix:find("2020") or primaries:find("2020") or primaries:find("dci-p3") then
        if sig_peak > 1.05 or gamma:find("pq") or gamma:find("hlg") then
            return true
        end
    end

    if sig_peak > 1.05 then
        return true
    end

    return false
end

-- Main toggle and hardware filter dispatcher
local function toggle_hdr()
    -- Guard: Prevent running on still images, pure audio, or album art
    local vtrack = mp.get_property_native("current-tracks/video")
    if not vtrack or vtrack.image or vtrack.albumart then
        mp.osd_message("NVIDIA True HDR: Not applicable for static images or audio", 2)
        return
    end

    local video_w = mp.get_property_native("width")
    if not video_w or video_w <= 0 then
        mp.osd_message("NVIDIA True HDR: No video stream loaded", 2)
        return
    end

    -- 1. If True HDR is currently active, turn it OFF
    if is_hdr_active() then
        remove_hdr_filter()
        mp.osd_message("NVIDIA True HDR: OFF", 2)
        return
    end

    -- 2. Abort if the video already contains native HDR mastering
    if is_native_hdr() then
        mp.osd_message("NVIDIA True HDR: Skipped (Content is already native HDR)", 3)
        return
    end

    -- 3. Append filter using isolated instance label
    local filter_cmd = string.format("%s:d3d11vpp=nvidia-true-hdr", hdr_label)
    mp.commandv("vf", "append", filter_cmd)

    mp.osd_message("NVIDIA True HDR: Active (SDR -> HDR)", 2)
end

-- Automatically clean filter when loading a new file to prevent carrying over to native HDR media
local function on_file_loaded()
    remove_hdr_filter()
end

mp.register_event("file-loaded", on_file_loaded)

-- Script Message API Handlers
mp.register_script_message("autohdr-toggle", toggle_hdr)
mp.register_script_message("autohdr-enable", function()
    if not is_hdr_active() and not is_native_hdr() then
        toggle_hdr()
    end
end)
mp.register_script_message("autohdr-disable", remove_hdr_filter)