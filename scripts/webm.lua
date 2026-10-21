-- =========================================================================
-- MPV Clip & WebM Maker - Modern NVIDIA NVENC Edition
-- Optimized for RTX Hardware Acceleration, AV1/HEVC/AVC & High-Speed Trimming
-- =========================================================================

local mp = require("mp")
local assdraw = require("mp.assdraw")
local msg = require("mp.msg")
local utils = require("mp.utils")
local mpopts = require("mp.options")

-- Default Configuration
local options = {
    keybind = "W",                      -- Shift + W
    output_directory = "",              -- Empty = same directory as source video
    run_detached = false,               -- Run encoding in background detached process
    output_template = "%F-[%s-%e]%M",   -- Filename template
    scale_height = -1,                  -- Target height (-1 = original source height)
    fps = -1,                           -- Target framerate (-1 = original source fps)
    
    -- Encoding & Bitrate Strategy
    target_filesize = 0,                -- in kB. 0 = Constant Quality (CQ/CRF mode)
    crf = 22,                           -- Constant Quality Factor (CQ for NVENC, CRF for CPU)
    strict_filesize_constraint = false,
    strict_bitrate_multiplier = 0.95,
    strict_audio_bitrate = 128,         -- in kbps
    
    -- Codec & NVIDIA Settings
    output_format = "avc-nvenc",        -- Default: avc-nvenc | hevc-nvenc | av1-nvenc | webm-vp9 | avc | hevc | av1 | gif | mp3 | raw
    nvenc_preset = "p6",                -- p1 (fastest) to p7 (slowest/highest quality). p6 is optimal
    nvenc_multipass = "qres",           -- disabled | qres (quarter-res 2-pass) | fullres (full 2-pass)
    nvenc_spatial_aq = true,            -- Enable Spatial Adaptive Quantization
    nvenc_temporal_aq = true,           -- Enable Temporal Adaptive Quantization
    
    -- General Settings
    twopass = false,                    -- Only used for CPU encoders (libvpx/libx264/libx265)
    apply_current_filters = true,       -- Bake in playback video filters (rotations, deinterlace, etc.)
    write_filename_on_metadata = false,
    threads = 0,                        -- CPU threads (0 = auto)
    additional_flags = "",
    non_strict_additional_flags = "",
    display_progress = "auto",          -- "auto", true, or false
    font_size = 22,
    margin = 14,
    message_duration = 4,
    gif_dither = 2,                     -- 0-5 for bayer w/ bayer_scale, 6 for sierra2_4a
    force_square_pixels = false
}

mpopts.read_options(options, "webm")

local is_windows = package.config:sub(1, 1) == "\\"

-- =========================================================================
-- Helper Utilities
-- =========================================================================

local function bold(text)
    return "{\\b1}" .. tostring(text) .. "{\\b0}"
end

local function message(text, duration)
    local ass = mp.get_property_osd("osd-ass-cc/0") or ""
    mp.osd_message(ass .. text, duration or options.message_duration)
end

local function file_exists(path)
    if not path or path == "" then return false end
    local info, _ = utils.file_info(path)
    return info ~= nil
end

local function format_time(seconds, no_ms, full)
    if not seconds or seconds < 0 then return "00:00" end
    local ms = no_ms and "" or string.format(".%03d", math.floor((seconds % 1) * 1000))
    local s = math.floor(seconds) % 60
    local m = math.floor(seconds / 60) % 60
    local h = math.floor(seconds / 3600)
    if full or h > 0 then
        return string.format("%d:%02d:%02d%s", h, m, s, ms)
    end
    return string.format("%02d:%02d%s", m, s, ms)
end

local function seconds_to_path_element(seconds, no_ms)
    local str = format_time(seconds, no_ms, false)
    return (str:gsub(":", "."))
end

local function parse_directory(dir)
    if not dir or dir == "" then return "" end
    local home = os.getenv("USERPROFILE") or os.getenv("HOME") or ""
    return (dir:gsub("^~", home))
end

local function shell_escape(args)
    local out = {}
    for _, a in ipairs(args) do
        local s = tostring(a)
        if s:find("[^%w_/:=-]") then
            if is_windows then
                s = '"' .. s:gsub('"', '\\"') .. '"'
            else
                s = "'" .. s:gsub("'", "'\\''") .. "'"
            end
        end
        table.insert(out, s)
    end
    local result = table.concat(out, " ")
    return is_windows and ('"' .. result .. '"') or result
end

-- Base64 Encode / Decode for VP8 legacy stats
local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64_encode(data)
    return ((data:gsub('.', function(x) 
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6 - i) or 0) end
        return b64_chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function base64_decode(data)
    data = data:gsub('[^' .. b64_chars .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b64_chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2^i - f % 2^(i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2^(8 - i) or 0) end
        return string.char(c)
    end))
end

-- =========================================================================
-- Video Geometry & Coordinate Mapping
-- =========================================================================

local dimensions_cache = nil

local function update_dimensions()
    local video_params = mp.get_property_native("video-out-params")
    if not video_params then return nil end

    local w = video_params["w"]
    local h = video_params["h"]
    local dw = video_params["dw"]
    local dh = video_params["dh"]
    if (mp.get_property_number("video-rotate", 0) % 180) == 90 then
        w, h = h, w
        dw, dh = dh, dw
    end

    local window_w, window_h = mp.get_osd_size()
    if not window_w or window_w == 0 then return nil end

    local keep_aspect = mp.get_property_bool("keepaspect", true)
    local dims = {
        top_left = { x = 0, y = 0 },
        bottom_right = { x = window_w, y = window_h },
        ratios = { w = 1, h = 1 }
    }

    if keep_aspect then
        local fwidth = window_w
        local fheight = math.floor(window_w / dw * dh)
        if fheight > window_h or fheight < h then
            local tmpw = math.floor(window_h / dh * dw)
            if tmpw <= window_w then
                fheight = window_h
                fwidth = tmpw
            end
        end

        local vo_panscan_area = window_h - fheight
        local f_w, f_h = fwidth / fheight, 1
        if vo_panscan_area == 0 then
            vo_panscan_area = window_h - fwidth
            f_w, f_h = 1, fheight / fwidth
        end

        local panscan = mp.get_property_number("panscan", 0)
        local scaled_w = fwidth + math.floor(vo_panscan_area * panscan * f_w)
        local scaled_h = fheight + math.floor(vo_panscan_area * panscan * f_h)

        local zoom = mp.get_property_number("video-zoom", 0)
        local pan_x = mp.get_property_number("video-pan-x", 0)
        local pan_y = mp.get_property_number("video-pan-y", 0)
        local align_x = mp.get_property_number("video-align-x", 0)
        local align_y = mp.get_property_number("video-align-y", 0)

        local function split_scale(dst_size, src_size, z, align, pan)
            src_size = math.floor(src_size * (2 ^ z))
            align = (align + 1) / 2
            local start = math.floor((dst_size - src_size) * align + pan * src_size)
            return start, start + src_size
        end

        dims.top_left.x, dims.bottom_right.x = split_scale(window_w, scaled_w, zoom, align_x, pan_x)
        dims.top_left.y, dims.bottom_right.y = split_scale(window_h, scaled_h, zoom, align_y, pan_y)
    end

    local actual_w = dims.bottom_right.x - dims.top_left.x
    local actual_h = dims.bottom_right.y - dims.top_left.y
    dims.ratios.w = actual_w > 0 and (w / actual_w) or 1
    dims.ratios.h = actual_h > 0 and (h / actual_h) or 1

    dimensions_cache = dims
    return dims
end

local function get_video_dimensions()
    return dimensions_cache or update_dimensions()
end

local function clamp(val, min_v, max_v)
    return math.max(min_v, math.min(val, max_v))
end

-- =========================================================================
-- Region & Crop Abstraction
-- =========================================================================

local Region = {}
Region.__index = Region

function Region.new()
    return setmetatable({ x = -1, y = -1, w = -1, h = -1 }, Region)
end

function Region:is_valid()
    return self.x >= 0 and self.y >= 0 and self.w > 0 and self.h > 0
end

function Region:set_from_points(p1, p2)
    self.x = math.min(p1.x, p2.x)
    self.y = math.min(p1.y, p2.y)
    self.w = math.abs(p1.x - p2.x)
    self.h = math.abs(p1.y - p2.y)
end

local Point = {}
Point.__index = Point

function Point.new(x, y)
    return setmetatable({ x = x or -1, y = y or -1 }, Point)
end

function Point:set_from_screen(sx, sy)
    local d = get_video_dimensions()
    if not d then return end
    local cx = clamp(sx, d.top_left.x, d.bottom_right.x)
    local cy = clamp(sy, d.top_left.y, d.bottom_right.y)
    self.x = math.floor(d.ratios.w * (cx - d.top_left.x) + 0.5)
    self.y = math.floor(d.ratios.h * (cy - d.top_left.y) + 0.5)
end

function Point:to_screen()
    local d = get_video_dimensions()
    if not d then return { x = 0, y = 0 } end
    return {
        x = math.floor(self.x / d.ratios.w + d.top_left.x + 0.5),
        y = math.floor(self.y / d.ratios.h + d.top_left.y + 0.5)
    }
end

-- =========================================================================
-- Format Engine & Modern Hardware Profiles
-- =========================================================================

local formats = {}

local function create_format(def)
    return {
        id = def.id,
        displayName = def.displayName,
        videoCodec = def.videoCodec or "",
        audioCodec = def.audioCodec or "",
        outputExtension = def.outputExtension or "mp4",
        isNvenc = def.isNvenc or false,
        supportsTwopass = def.supportsTwopass or false,
        acceptsBitrate = def.acceptsBitrate ~= false,
        getFlags = def.getFlags or function() return {} end,
        getPreFilters = def.getPreFilters or function() return {} end,
        getPostFilters = def.getPostFilters or function() return {} end,
        postCommandModifier = def.postCommandModifier or function(_, cmd) return cmd end
    }
end

-- 1. Modern NVIDIA Hardware Encoders
formats["av1-nvenc"] = create_format({
    id = "av1-nvenc",
    displayName = "AV1 (NVIDIA NVENC RTX 40+)",
    videoCodec = "av1_nvenc",
    audioCodec = "libopus",
    outputExtension = "mp4",
    isNvenc = true,
    supportsTwopass = false
})

formats["hevc-nvenc"] = create_format({
    id = "hevc-nvenc",
    displayName = "HEVC / H.265 (NVIDIA NVENC)",
    videoCodec = "hevc_nvenc",
    audioCodec = "aac",
    outputExtension = "mp4",
    isNvenc = true,
    supportsTwopass = false
})

formats["avc-nvenc"] = create_format({
    id = "avc-nvenc",
    displayName = "AVC / H.264 (NVIDIA NVENC Universal)",
    videoCodec = "h264_nvenc",
    audioCodec = "aac",
    outputExtension = "mp4",
    isNvenc = true,
    supportsTwopass = false
})

-- 2. Open Web Standards
formats["webm-vp9"] = create_format({
    id = "webm-vp9",
    displayName = "WebM (VP9 / Opus)",
    videoCodec = "libvpx-vp9",
    audioCodec = "libopus",
    outputExtension = "webm",
    supportsTwopass = false,
    getFlags = function()
        return { "--ovcopts-add=threads=" .. tostring(options.threads > 0 and options.threads or 4) }
    end
})

formats["webm-vp8"] = create_format({
    id = "webm-vp8",
    displayName = "WebM Legacy (VP8 / Vorbis)",
    videoCodec = "libvpx",
    audioCodec = "libvorbis",
    outputExtension = "webm",
    supportsTwopass = true,
    getFlags = function()
        return {
            "--ovcopts-add=threads=" .. tostring(options.threads > 0 and options.threads or 4),
            "--ovcopts-add=auto-alt-ref=1",
            "--ovcopts-add=lag-in-frames=25"
        }
    end
})

-- 3. High-Quality Software CPU Encoders
formats["avc"] = create_format({
    id = "avc",
    displayName = "AVC (CPU libx264 / AAC)",
    videoCodec = "libx264",
    audioCodec = "aac",
    outputExtension = "mp4",
    supportsTwopass = true
})

formats["hevc"] = create_format({
    id = "hevc",
    displayName = "HEVC (CPU libx265 / AAC)",
    videoCodec = "libx265",
    audioCodec = "aac",
    outputExtension = "mp4",
    supportsTwopass = true
})

formats["av1"] = create_format({
    id = "av1",
    displayName = "AV1 (CPU libaom-av1 / Opus)",
    videoCodec = "libaom-av1",
    audioCodec = "libopus",
    outputExtension = "mp4",
    supportsTwopass = true
})

-- 4. High Quality Palette-Optimized GIF
formats["gif"] = create_format({
    id = "gif",
    displayName = "GIF (Palette-Generated)",
    videoCodec = "gif",
    audioCodec = "",
    outputExtension = "gif",
    acceptsBitrate = false,
    supportsTwopass = false,
    postCommandModifier = function(_, cmd, _, start_t, end_t)
        local new_cmd = {}
        local start_ts = format_time(start_t, false, true):gsub(":", "\\\\:")
        local end_ts = format_time(end_t, false, true):gsub(":", "\\\\:")
        local cfilter = "[vid1]trim=start=" .. start_ts .. ":end=" .. end_ts .. "[vidtmp];"
        
        for _, v in ipairs(cmd) do
            if v:match("^%-%-vf%-add=lavfi%-") or v:match("^%-%-vf%-add=fps") then
                local n = v:gsub("^%-%-vf%-add=", ""):gsub("^lavfi%-", "")
                cfilter = cfilter .. "[vidtmp]" .. n .. "[vidtmp];"
            elseif not v:match("^%-%-deinterlace=") then
                table.insert(new_cmd, v)
            end
        end

        cfilter = cfilter .. "[vidtmp]split[topal][vidf];[topal]palettegen=stats_mode=diff[pal];[vidf][pal]paletteuse=diff_mode=rectangle"
        if options.gif_dither ~= 6 then
            cfilter = cfilter .. ":dither=bayer:bayer_scale=" .. tostring(options.gif_dither)
        end
        cfilter = cfilter .. "[vo]"
        table.insert(new_cmd, "--lavfi-complex=" .. cfilter)
        return new_cmd
    end
})

formats["mp3"] = create_format({
    id = "mp3",
    displayName = "Audio Only (MP3)",
    videoCodec = "",
    audioCodec = "libmp3lame",
    outputExtension = "mp3"
})

formats["raw"] = create_format({
    id = "raw",
    displayName = "Raw Uncompressed",
    videoCodec = "rawvideo",
    audioCodec = "pcm_s16le",
    outputExtension = "avi",
    acceptsBitrate = false
})

local format_keys = {
    "avc-nvenc",
    "hevc-nvenc",
    "av1-nvenc",
    "webm-vp9",
    "avc",
    "hevc",
    "av1",
    "gif",
    "mp3",
    "raw"
}

-- =========================================================================
-- UI Framework & Dynamic OSD Pages
-- =========================================================================

local function get_scale_factor()
    local _, osd_h = mp.get_osd_size()
    return math.max(0.65, (osd_h or 720) / 720)
end

local Page = {}
Page.__index = Page

function Page.new()
    return setmetatable({ visible = false, keybinds = {} }, Page)
end

function Page:add_keybinds()
    for key, fn in pairs(self.keybinds) do
        mp.add_forced_key_binding(key, "webm_" .. key, fn, { repeatable = true })
    end
end

function Page:remove_keybinds()
    for key in pairs(self.keybinds) do
        mp.remove_key_binding("webm_" .. key)
    end
end

function Page:setup_text(ass)
    local scale = get_scale_factor()
    local m = math.floor(options.margin * scale)
    ass:append("{\\an7}")
    ass:pos(m, m)
    ass:append("{\\fnSegoe UI\\b0\\fs" .. tostring(math.floor(options.font_size * scale)) .. "\\bord1.5\\3c&H000000&\\shad1}")
end

function Page:clear()
    local w, h = mp.get_osd_size()
    if w and h then mp.set_osd_ass(w, h, "") end
end

function Page:show()
    if self.visible then return end
    self.visible = true
    self:add_keybinds()
    self:clear()
    self:draw()
end

function Page:hide()
    if not self.visible then return end
    self.visible = false
    self:remove_keybinds()
    self:clear()
end

-- =========================================================================
-- Crop Page
-- =========================================================================

local CropPage = setmetatable({}, { __index = Page })
CropPage.__index = CropPage

function CropPage.new(callback, current_region)
    local self = setmetatable(Page.new(), CropPage)
    self.callback = callback
    self.pointA = Point.new()
    self.pointB = Point.new()

    self.keybinds = {
        ["1"] = function() self:set_point_a() end,
        ["2"] = function() self:set_point_b() end,
        ["r"] = function() self:reset() end,
        ["ESC"] = function() self:cancel() end,
        ["ENTER"] = function() self:confirm() end
    }

    self:reset()
    if current_region and current_region:is_valid() then
        self.pointA.x = current_region.x
        self.pointA.y = current_region.y
        self.pointB.x = current_region.x + current_region.w
        self.pointB.y = current_region.y + current_region.h
    end
    return self
end

function CropPage:reset()
    local d = get_video_dimensions()
    if d then
        self.pointA:set_from_screen(d.top_left.x, d.top_left.y)
        self.pointB:set_from_screen(d.bottom_right.x, d.bottom_right.y)
    end
    if self.visible then self:draw() end
end

function CropPage:set_point_a()
    local x, y = mp.get_mouse_pos()
    self.pointA:set_from_screen(x, y)
    if self.visible then self:draw() end
end

function CropPage:set_point_b()
    local x, y = mp.get_mouse_pos()
    self.pointB:set_from_screen(x, y)
    if self.visible then self:draw() end
end

function CropPage:cancel()
    self:hide()
    self.callback(false, nil)
end

function CropPage:confirm()
    local r = Region.new()
    r:set_from_points(self.pointA, self.pointB)
    self:hide()
    self.callback(true, r)
end

function CropPage:draw()
    local w, h = mp.get_osd_size()
    local d = get_video_dimensions()
    if not w or not d then return end

    local ass = assdraw.ass_new()
    local r = Region.new()
    r:set_from_points(self.pointA:to_screen(), self.pointB:to_screen())

    -- Semi-transparent darkened bounds outside crop
    ass:new_event()
    ass:append("{\\an7\\bord0\\shad0\\c&H000000&\\alpha&H77&}")
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(d.top_left.x, d.top_left.y, r.x, r.y + r.h)
    ass:rect_cw(r.x, d.top_left.y, d.bottom_right.x, r.y)
    ass:rect_cw(d.top_left.x, r.y + r.h, r.x + r.w, d.bottom_right.y)
    ass:rect_cw(r.x + r.w, r.y, d.bottom_right.x, d.bottom_right.y)
    ass:draw_stop()

    -- Crop Header HUD
    ass:new_event()
    self:setup_text(ass)
    ass:append("{\\b1\\c&H00D7FF&}Interactive Crop Region{\\b0\\c&HFFFFFF&}\\N\\N")
    ass:append(bold("1: ") .. "Set Top-Left (" .. self.pointA.x .. ", " .. self.pointA.y .. ")\\N")
    ass:append(bold("2: ") .. "Set Bottom-Right (" .. self.pointB.x .. ", " .. self.pointB.y .. ")\\N")
    ass:append(bold("r: ") .. "Reset Fullscreen\\N")
    ass:append(bold("ESC: ") .. "Cancel\\N")
    ass:append("{\\b1\\c&H78C850&}ENTER: Confirm (" .. math.abs(self.pointA.x - self.pointB.x) .. "x" .. math.abs(self.pointA.y - self.pointB.y) .. "){\\b0\\c&HFFFFFF&}\\N")

    mp.set_osd_ass(w, h, ass.text)
end

-- =========================================================================
-- Options Interface
-- =========================================================================

local OptionItem = {}
OptionItem.__index = OptionItem

function OptionItem.new(optType, text, value, cfg, visible_fn)
    return setmetatable({
        optType = optType,
        text = text,
        value = value,
        cfg = cfg or {},
        visible_fn = visible_fn or function() return true end
    }, OptionItem)
end

function OptionItem:left()
    if self.optType == "bool" then
        self.value = not self.value
    elseif self.optType == "int" then
        self.value = self.value - (self.cfg.step or 1)
        if self.cfg.min and self.value < self.cfg.min then self.value = self.cfg.min end
    elseif self.optType == "list" then
        for i, item in ipairs(self.cfg.values) do
            if item[1] == self.value and i > 1 then
                self.value = self.cfg.values[i - 1][1]
                break
            end
        end
    end
end

function OptionItem:right()
    if self.optType == "bool" then
        self.value = not self.value
    elseif self.optType == "int" then
        self.value = self.value + (self.cfg.step or 1)
        if self.cfg.max and self.value > self.cfg.max then self.value = self.cfg.max end
    elseif self.optType == "list" then
        for i, item in ipairs(self.cfg.values) do
            if item[1] == self.value and i < #self.cfg.values then
                self.value = self.cfg.values[i + 1][1]
                break
            end
        end
    end
end

function OptionItem:get_display()
    if self.optType == "bool" then
        return self.value and "{\\c&H78C850&}Yes{\\c&HFFFFFF&}" or "{\\c&H5050C8&}No{\\c&HFFFFFF&}"
    elseif self.optType == "int" then
        if self.cfg.labels and self.cfg.labels[self.value] then
            return self.cfg.labels[self.value]
        end
        return tostring(self.value)
    elseif self.optType == "list" then
        for _, item in ipairs(self.cfg.values) do
            if item[1] == self.value then
                return item[2] or tostring(item[1])
            end
        end
    end
    return tostring(self.value)
end

local OptionsPage = setmetatable({}, { __index = Page })
OptionsPage.__index = OptionsPage

function OptionsPage.new(callback)
    local self = setmetatable(Page.new(), OptionsPage)
    self.callback = callback
    self.selected = 1

    local format_vals = {}
    for _, k in ipairs(format_keys) do
        table.insert(format_vals, { k, formats[k].displayName })
    end

    local nvenc_presets = {
        { "p1", "p1 (Fastest / Lowest Quality)" },
        { "p2", "p2 (Faster)" },
        { "p3", "p3 (Fast)" },
        { "p4", "p4 (Medium Default)" },
        { "p5", "p5 (Slow / High Quality)" },
        { "p6", "p6 (Optimal RTX HQ)" },
        { "p7", "p7 (Highest Quality)" }
    }

    local nvenc_multipass_opts = {
        { "disabled", "Disabled (Single Pass)" },
        { "qres", "Quarter-Res Multi-Pass (Balanced)" },
        { "fullres", "Full-Res Multi-Pass (Slow / Max Detail)" }
    }

    local scale_opts = {
        { -1, "Source / No Scale" },
        { 480, "480p" },
        { 720, "720p" },
        { 1080, "1080p (Full HD)" },
        { 1440, "1440p (2K QHD)" },
        { 2160, "2160p (4K UHD)" }
    }

    local fps_opts = {
        { -1, "Source FPS" },
        { 24, "24 fps" },
        { 30, "30 fps" },
        { 60, "60 fps" },
        { 120, "120 fps" }
    }

    self.items = {
        { "output_format", OptionItem.new("list", "Encoder Format", options.output_format, { values = format_vals }) },
        { "nvenc_preset", OptionItem.new("list", "NVIDIA NVENC Preset", options.nvenc_preset, { values = nvenc_presets }, function()
            return formats[options.output_format].isNvenc
        end) },
        { "nvenc_multipass", OptionItem.new("list", "NVIDIA Multi-pass", options.nvenc_multipass, { values = nvenc_multipass_opts }, function()
            return formats[options.output_format].isNvenc
        end) },
        { "target_filesize", OptionItem.new("int", "Target Filesize", options.target_filesize, { step = 2500, min = 0, labels = { [0] = "Constant Quality (CQ Mode)" } }) },
        { "crf", OptionItem.new("int", "CQ / CRF Quality (Lower = Better)", options.crf, { step = 1, min = 0, max = 51 }) },
        { "scale_height", OptionItem.new("list", "Scale Output Height", options.scale_height, { values = scale_opts }) },
        { "fps", OptionItem.new("list", "Framerate", options.fps, { values = fps_opts }) },
        { "apply_current_filters", OptionItem.new("bool", "Apply Playback Video Filters", options.apply_current_filters) },
        { "twopass", OptionItem.new("bool", "CPU 2-Pass Mode", options.twopass, nil, function()
            return not formats[options.output_format].isNvenc and formats[options.output_format].supportsTwopass
        end) }
    }

    self.keybinds = {
        ["UP"] = function() self:prev() end,
        ["DOWN"] = function() self:next() end,
        ["LEFT"] = function() self:left() end,
        ["RIGHT"] = function() self:right() end,
        ["ENTER"] = function() self:confirm() end,
        ["ESC"] = function() self:cancel() end
    }

    return self
end

function OptionsPage:prev()
    for i = self.selected - 1, 1, -1 do
        if self.items[i][2].visible_fn() then
            self.selected = i
            break
        end
    end
    self:draw()
end

function OptionsPage:next()
    for i = self.selected + 1, #self.items do
        if self.items[i][2].visible_fn() then
            self.selected = i
            break
        end
    end
    self:draw()
end

function OptionsPage:left()
    self.items[self.selected][2]:left()
    options[self.items[self.selected][1]] = self.items[self.selected][2].value
    self:draw()
end

function OptionsPage:right()
    self.items[self.selected][2]:right()
    options[self.items[self.selected][1]] = self.items[self.selected][2].value
    self:draw()
end

function OptionsPage:confirm()
    self:hide()
    self.callback(true)
end

function OptionsPage:cancel()
    self:hide()
    self.callback(false)
end

function OptionsPage:draw()
    local w, h = mp.get_osd_size()
    if not w then return end

    local ass = assdraw.ass_new()
    ass:new_event()
    self:setup_text(ass)
    ass:append("{\\b1\\c&H00D7FF&}Encode & NVIDIA Hardware Settings{\\b0\\c&HFFFFFF&}\\N\\N")

    for i, item in ipairs(self.items) do
        local opt = item[2]
        if opt.visible_fn() then
            local is_sel = self.selected == i
            local prefix = is_sel and "{\\b1\\c&H00D7FF&}▶ " or "   "
            local label_color = is_sel and "{\\c&HFFFFFF&}" or "{\\c&HD0D0D0&}"
            ass:append(prefix .. label_color .. opt.text .. ": {\\b1}" .. opt:get_display() .. "{\\b0\\c&HFFFFFF&}\\N")
        end
    end

    ass:append("\\N{\\c&H888888&}▲ / ▼: Navigate  |  ◀ / ▶: Change  |  ENTER: Save  |  ESC: Cancel{\\c&HFFFFFF&}\\N")
    mp.set_osd_ass(w, h, ass.text)
end

-- =========================================================================
-- Loop Preview Page
-- =========================================================================

local PreviewPage = setmetatable({}, { __index = Page })
PreviewPage.__index = PreviewPage

function PreviewPage.new(callback, region, start_t, end_t)
    local self = setmetatable(Page.new(), PreviewPage)
    self.callback = callback
    self.region = region
    self.start_t = start_t
    self.end_t = end_t
    self.saved_pause = mp.get_property_native("pause")
    self.saved_vf = mp.get_property_native("vf") or {}

    self.keybinds = {
        ["ESC"] = function() self:stop() end,
        ["p"] = function() self:stop() end
    }
    return self
end

function PreviewPage:start()
    local vf = utils.shared_script_property("vf") or mp.get_property_native("vf") or {}
    table.insert(vf, { name = "sub" })
    if self.region and self.region:is_valid() then
        table.insert(vf, {
            name = "crop",
            params = {
                w = tostring(self.region.w),
                h = tostring(self.region.h),
                x = tostring(self.region.x),
                y = tostring(self.region.y)
            }
        })
    end

    mp.set_property_native("vf", vf)
    if self.start_t >= 0 and self.end_t > self.start_t then
        mp.set_property_native("ab-loop-a", self.start_t)
        mp.set_property_native("ab-loop-b", self.end_t)
        mp.set_property_native("time-pos", self.start_t)
    end
    mp.set_property_native("pause", false)
    self:show()
end

function PreviewPage:stop()
    mp.set_property("ab-loop-a", "no")
    mp.set_property("ab-loop-b", "no")
    mp.set_property_native("vf", self.saved_vf)
    mp.set_property_native("pause", self.saved_pause)
    self:hide()
    self.callback()
end

function PreviewPage:draw()
    local w, h = mp.get_osd_size()
    local ass = assdraw.ass_new()
    ass:new_event()
    self:setup_text(ass)
    ass:append("{\\b1\\c&H78C850&}Previewing Selection (Loop Active){\\b0\\c&HFFFFFF&}\\N")
    ass:append("Press " .. bold("ESC") .. " or " .. bold("p") .. " to exit preview.\\N")
    mp.set_osd_ass(w, h, ass.text)
end

-- =========================================================================
-- Main Dashboard Controller
-- =========================================================================

local MainPage = setmetatable({}, { __index = Page })
MainPage.__index = MainPage

function MainPage.new()
    local self = setmetatable(Page.new(), MainPage)
    self.startTime = -1
    self.endTime = -1
    self.region = Region.new()

    self.keybinds = {
        ["1"] = function() self:set_start() end,
        ["2"] = function() self:set_end() end,
        ["!"] = function() self:jump_start() end,
        ["@"] = function() self:jump_end() end,
        ["c"] = function() self:crop() end,
        ["o"] = function() self:open_options() end,
        ["p"] = function() self:preview() end,
        ["e"] = function() self:start_encode() end,
        ["ESC"] = function() self:hide() end
    }
    return self
end

function MainPage:set_start()
    self.startTime = mp.get_property_number("time-pos", 0)
    self:draw()
end

function MainPage:set_end()
    self.endTime = mp.get_property_number("time-pos", 0)
    self:draw()
end

function MainPage:jump_start()
    if self.startTime >= 0 then mp.set_property_number("time-pos", self.startTime) end
end

function MainPage:jump_end()
    if self.endTime >= 0 then mp.set_property_number("time-pos", self.endTime) end
end

function MainPage:crop()
    self:hide()
    local page = CropPage.new(function(confirmed, region)
        if confirmed and region then self.region = region end
        self:show()
    end, self.region)
    page:show()
end

function MainPage:open_options()
    self:hide()
    local page = OptionsPage.new(function()
        self:show()
    end)
    page:show()
end

function MainPage:preview()
    self:hide()
    local page = PreviewPage.new(function()
        self:show()
    end, self.region, self.startTime, self.endTime)
    page:start()
end

function MainPage:draw()
    local w, h = mp.get_osd_size()
    if not w then return end

    local start_str = self.startTime >= 0 and format_time(self.startTime) or "Not Set"
    local end_str = self.endTime >= 0 and format_time(self.endTime) or "Not Set"
    local diff_str = (self.startTime >= 0 and self.endTime > self.startTime) and string.format("%.2fs", self.endTime - self.startTime) or "--"
    local fmt = formats[options.output_format]

    local ass = assdraw.ass_new()
    ass:new_event()
    self:setup_text(ass)
    ass:append("{\\b1\\c&H00D7FF&}⚡ MPV Clip Maker (NVIDIA RTX Edition){\\b0\\c&HFFFFFF&}\\N\\N")
    ass:append(bold("1: ") .. "Set Start Time (" .. start_str .. ")  |  " .. bold("!: ") .. "Jump\\N")
    ass:append(bold("2: ") .. "Set End Time   (" .. end_str .. ")  |  " .. bold("@: ") .. "Jump\\N")
    ass:append("Duration: {\\b1\\c&H78C850&}" .. diff_str .. "{\\b0\\c&HFFFFFF&}\\N\\N")

    local crop_desc = self.region:is_valid() and (self.region.w .. "x" .. self.region.h .. " at (" .. self.region.x .. "," .. self.region.y .. ")") or "Fullscreen"
    ass:append(bold("c: ") .. "Crop Region: {\\c&HD0D0D0&}" .. crop_desc .. "{\\c&HFFFFFF&}\\N")
    ass:append(bold("o: ") .. "Format: {\\b1\\c&H3BB0FF&}" .. fmt.displayName .. "{\\b0\\c&HFFFFFF&}\\N\\N")

    ass:append(bold("p: ") .. "Loop Preview\\N")
    ass:append("{\\b1\\c&H78C850&}" .. bold("e: ") .. "Start Encode{\\b0\\c&HFFFFFF&}\\N\\N")
    ass:append("{\\c&H888888&}" .. bold("ESC: ") .. "Close Toolkit{\\c&HFFFFFF&}\\N")

    mp.set_osd_ass(w, h, ass.text)
end

-- =========================================================================
-- Execution & Encoding Pipeline
-- =========================================================================

local function generate_output_path(start_t, end_t, fmt)
    local dir = options.output_directory ~= "" and parse_directory(options.output_directory) or ""
    local src_path = mp.get_property("path") or ""

    if dir == "" then
        if file_exists(src_path) then
            dir, _ = utils.split_path(src_path)
        else
            dir = parse_directory("~")
        end
    end

    local name = options.output_template
    name = name:gsub("%%f", mp.get_property("filename", "clip"))
    name = name:gsub("%%F", mp.get_property("filename/no-ext", "clip"))
    name = name:gsub("%%s", seconds_to_path_element(start_t, false))
    name = name:gsub("%%S", seconds_to_path_element(start_t, true))
    name = name:gsub("%%e", seconds_to_path_element(end_t, false))
    name = name:gsub("%%E", seconds_to_path_element(end_t, true))
    name = name:gsub("%%M", fmt.audioCodec ~= "" and "-audio" or "")
    name = name:gsub("[<>:\"/\\|?*]", "")

    return utils.join_path(dir, name .. "." .. fmt.outputExtension)
end

function MainPage:start_encode()
    self:hide()

    if self.startTime < 0 or self.endTime <= self.startTime then
        message("Invalid start/end markers! Set both before encoding.", 3)
        return
    end

    local path = mp.get_property("path")
    if not path then
        message("No active playback stream.", 3)
        return
    end

    local fmt = formats[options.output_format]
    local out_path = generate_output_path(self.startTime, self.endTime, fmt)
    local duration = self.endTime - self.startTime

    local cmd = {
        "mpv",
        path,
        "--start=" .. format_time(self.startTime, false, true),
        "--end=" .. format_time(self.endTime, false, true),
        "--loop-file=no",
        "--no-pause"
    }

    -- Audio / Video Codec flags
    if fmt.videoCodec ~= "" then
        table.insert(cmd, "--ovc=" .. fmt.videoCodec)
    else
        table.insert(cmd, "--vid=no")
    end

    if fmt.audioCodec ~= "" and not mp.get_property_bool("mute", false) then
        table.insert(cmd, "--oac=" .. fmt.audioCodec)
    else
        table.insert(cmd, "--aid=no")
    end

    -- Video Filter Chain
    local vf = {}
    if options.apply_current_filters then
        local cur_vf = mp.get_property_native("vf") or {}
        for _, f in ipairs(cur_vf) do
            if f.enabled ~= false and f.name then
                table.insert(vf, f.name)
            end
        end
    end

    if self.region:is_valid() then
        table.insert(vf, string.format("lavfi-crop=%d:%d:%d:%d", self.region.w, self.region.h, self.region.x, self.region.y))
    end

    if options.scale_height > 0 then
        table.insert(vf, "lavfi-scale=-2:" .. tostring(options.scale_height))
    end

    if options.fps > 0 then
        table.insert(vf, "fps=" .. tostring(options.fps))
    end

    for _, filter in ipairs(vf) do
        table.insert(cmd, "--vf-add=" .. filter)
    end

    -- Modern NVIDIA NVENC Optimization Flags
    if fmt.isNvenc then
        table.insert(cmd, "--ovcopts-add=preset=" .. options.nvenc_preset)
        table.insert(cmd, "--ovcopts-add=tune=hq")
        table.insert(cmd, "--ovcopts-add=multipass=" .. options.nvenc_multipass)
        if options.nvenc_spatial_aq then table.insert(cmd, "--ovcopts-add=spatial-aq=1") end
        if options.nvenc_temporal_aq then table.insert(cmd, "--ovcopts-add=temporal-aq=1") end

        if options.target_filesize <= 0 then
            -- True High-Quality CQ Rate Control
            table.insert(cmd, "--ovcopts-add=rc=vbr")
            table.insert(cmd, "--ovcopts-add=cq=" .. tostring(options.crf))
            table.insert(cmd, "--ovcopts-add=b=0")
        else
            -- Target Size Calculation
            local total_kbits = options.target_filesize * 8
            local audio_kbits = (fmt.audioCodec ~= "") and (duration * options.strict_audio_bitrate) or 0
            local video_br = math.floor((total_kbits - audio_kbits) / duration)
            table.insert(cmd, "--ovcopts-add=rc=vbr")
            table.insert(cmd, "--ovcopts-add=b=" .. tostring(video_br) .. "k")
            table.insert(cmd, "--ovcopts-add=maxrate=" .. tostring(math.floor(video_br * 1.5)) .. "k")
            if fmt.audioCodec ~= "" then
                table.insert(cmd, "--oacopts-add=b=" .. tostring(options.strict_audio_bitrate) .. "k")
            end
        end
    else
        -- Standard CPU Rate Control
        if options.target_filesize > 0 and fmt.acceptsBitrate then
            local video_br = math.floor((options.target_filesize * 8) / duration)
            table.insert(cmd, "--ovcopts-add=b=" .. tostring(video_br) .. "k")
        elseif options.crf >= 0 and fmt.acceptsBitrate then
            table.insert(cmd, "--ovcopts-add=crf=" .. tostring(options.crf))
        end
    end

    -- User Flags
    for token in string.gmatch(options.additional_flags, "[^%s]+") do
        table.insert(cmd, token)
    end

    cmd = fmt:postCommandModifier(cmd, self.region, self.startTime, self.endTime)
    table.insert(cmd, "--o=" .. out_path)

    msg.info("Executing Encode: " .. table.concat(cmd, " "))

    if options.run_detached then
        utils.subprocess_detached({ args = cmd })
        message("Encoding started detached in background...", 3)
    else
        message("Encoding with " .. fmt.displayName .. "...", 3)
        local res = utils.subprocess({ args = cmd, cancellable = false })
        if res.status == 0 then
            message("Encode Finished! Saved to:\\N" .. bold(out_path), 5)
        else
            message("Encode failed! Check MPV console logs.", 5)
        end
    end
end

-- =========================================================================
-- Entrypoint & Keybinding
-- =========================================================================

local main = MainPage.new()

mp.add_key_binding(options.keybind, "display-webm-encoder", function()
    main:show()
end, { repeatable = false })

mp.register_event("file-loaded", function()
    dimensions_cache = nil
    update_dimensions()
end)

local monitor_props = { "keepaspect", "video-out-params", "video-zoom", "video-pan-x", "video-pan-y" }
for _, p in ipairs(monitor_props) do
    mp.observe_property(p, "native", function()
        dimensions_cache = nil
    end)
end