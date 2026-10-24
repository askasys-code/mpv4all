-- =========================================================================
-- MPV Clip Maker (NVIDIA Suite Unified Edition)
-- Fast Clipping, Trimming & Encoding (AV1 / HEVC / H.264 / GIF)
-- High-Performance ASS Vector HUD & Standalone Portable Engine
-- =========================================================================

local mp = require("mp")
local assdraw = require("mp.assdraw")
local msg = require("mp.msg")
local utils = require("mp.utils")
local mpopts = require("mp.options")

-- Default Configuration
local options = {
    keybind = "W",                      -- Shift + W
    output_directory = "",              -- Empty = same directory as source file
    output_template = "%F-[%s-%e]%M",   -- Filename template
    scale_height = -1,                  -- Target height (-1 = keep source height)
    fps = -1,                           -- Target framerate (-1 = keep source fps)
    
    -- Encoding & Bitrate Strategy
    target_filesize = 0,                -- in kB. 0 = Constant Quality (CQP / CRF mode)
    crf = 22,                           -- Quality factor (CQ for NVENC, CRF for CPU)
    strict_filesize_constraint = false,
    strict_audio_bitrate = 128,         -- in kbps
    
    -- Subtitles & Hardware Handling
    burn_subtitles = false,             -- Hardcode/burn active subtitles into the video
    apply_current_filters = false,      -- Keep false to prevent D3D11/VSR display filter collisions
    
    -- Codec & NVIDIA Settings
    output_format = "avc-nvenc",        -- avc-nvenc | hevc-nvenc | av1-nvenc | webm-vp9 | avc | hevc | av1 | gif | mp3 | raw
    nvenc_preset = "p4",                -- p1 (fastest) to p7 (slowest). p4/p5/p6 recommended
    
    -- UI Styling (Matches nvidia-monitor, sound-monitor & video-monitor)
    ui_scale = 1.35,                    -- User size multiplier (1.0 = normal, 1.35 = 4K recommended, 1.6 = TV)
    font_face = "Segoe UI",
    message_duration = 4,
    gif_dither = 2                      -- 0-5 for bayer, 6 for sierra2_4a
}

mpopts.read_options(options, "clip_maker")

-- Visual Palette & Theme Configuration (Identical to Suite Monitors)
local cfg = {
    ui_scale        = options.ui_scale or 1.35,
    font_face       = options.font_face or "Segoe UI",
    color_green     = "00E676",         -- NVIDIA Green (Headers, Titles & Confirm)
    color_cyan      = "00E5FF",         -- RivaTuner Cyan (Values & Active Selections)
    color_yellow    = "00C8FF",         -- Amber Warning (Durations & Secondary Keys)
    color_red       = "3B3BFF",         -- Critical Red (Cancel / Abort)
    color_white     = "FFFFFF",
    color_gray      = "9E9E9E",         -- Descriptions & Inactive
    color_dark_box  = "1C1C1C",
    bg_alpha        = "35",             -- Glass box transparency (~80% dark)
}

local overlay = mp.create_osd_overlay("ass-events")
local is_encoding = false
local active_page_count = 0

-- =========================================================================
-- Helper Utilities
-- =========================================================================

local function bold(text)
    return "{\\b1}" .. tostring(text) .. "{\\b0}"
end

local function message(text, duration)
    mp.osd_message(text, duration or options.message_duration)
end

local function file_exists(path)
    if not path or path == "" then return false end
    local info, _ = utils.file_info(path)
    return info ~= nil
end

-- Resolve the mpv binary path dynamically for portable installations
local function get_mpv_binary()
    local exe_dir = mp.command_native({"expand-path", "~~exe_dir/"})
    if exe_dir and exe_dir ~= "" then
        local exe_win = utils.join_path(exe_dir, "mpv.exe")
        if file_exists(exe_win) then return exe_win end
        local exe_unix = utils.join_path(exe_dir, "mpv")
        if file_exists(exe_unix) then return exe_unix end
    end
    return "mpv"
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

local function truncate_string(str, max_len)
    if not str then return "" end
    if #str > max_len then return str:sub(1, max_len - 3) .. "..." end
    return str
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
-- Region & Point Abstraction
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
-- Formats Engine
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
        forceYuv420 = def.forceYuv420 or false,
        supportsTwopass = def.supportsTwopass or false,
        acceptsBitrate = def.acceptsBitrate ~= false,
        postCommandModifier = def.postCommandModifier or function(_, cmd) return cmd end
    }
end

formats["avc-nvenc"] = create_format({
    id = "avc-nvenc",
    displayName = "AVC / H.264 (NVIDIA NVENC)",
    videoCodec = "h264_nvenc",
    audioCodec = "aac",
    outputExtension = "mp4",
    isNvenc = true,
    forceYuv420 = true
})

formats["hevc-nvenc"] = create_format({
    id = "hevc-nvenc",
    displayName = "HEVC / H.265 (NVIDIA NVENC)",
    videoCodec = "hevc_nvenc",
    audioCodec = "aac",
    outputExtension = "mp4",
    isNvenc = true
})

formats["av1-nvenc"] = create_format({
    id = "av1-nvenc",
    displayName = "AV1 (NVIDIA NVENC RTX 40+)",
    videoCodec = "av1_nvenc",
    audioCodec = "libopus",
    outputExtension = "mp4",
    isNvenc = true
})

formats["webm-vp9"] = create_format({
    id = "webm-vp9",
    displayName = "WebM (VP9 / Opus)",
    videoCodec = "libvpx-vp9",
    audioCodec = "libopus",
    outputExtension = "webm"
})

formats["webm-vp8"] = create_format({
    id = "webm-vp8",
    displayName = "WebM Legacy (VP8 / Vorbis)",
    videoCodec = "libvpx",
    audioCodec = "libvorbis",
    outputExtension = "webm",
    supportsTwopass = true
})

formats["avc"] = create_format({
    id = "avc",
    displayName = "AVC (CPU libx264 / AAC)",
    videoCodec = "libx264",
    audioCodec = "aac",
    outputExtension = "mp4",
    forceYuv420 = true,
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

formats["gif"] = create_format({
    id = "gif",
    displayName = "GIF (Palette-Generated)",
    videoCodec = "gif",
    audioCodec = "",
    outputExtension = "gif",
    acceptsBitrate = false,
    postCommandModifier = function(_, cmd)
        local new_cmd = {}
        local lavfi_filters = {}

        for _, v in ipairs(cmd) do
            if v:match("^%-%-vf%-add=lavfi%-") or v:match("^%-%-vf%-add=fps") then
                local n = v:gsub("^%-%-vf%-add=", ""):gsub("^lavfi%-", "")
                table.insert(lavfi_filters, n)
            elseif not v:match("^%-%-deinterlace=") then
                table.insert(new_cmd, v)
            end
        end

        local cfilter = ""
        local current_node = "[vid1]"
        if #lavfi_filters > 0 then
            for idx, flt in ipairs(lavfi_filters) do
                local next_node = "[v" .. tostring(idx) .. "]"
                cfilter = cfilter .. current_node .. flt .. next_node .. ";"
                current_node = next_node
            end
        end

        cfilter = cfilter .. current_node .. "split[topal][vidf];[topal]palettegen=stats_mode=diff[pal];[vidf][pal]paletteuse=diff_mode=rectangle"
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
-- Unified ASS Glass Card Rendering Engine
-- Placed at Bottom-Left, cleanly docked beneath video-monitor without overlap
-- =========================================================================

local function render_glass_card(params)
    local d = mp.get_property_native("osd-dimensions")
    if not d or d.w == 0 or d.h == 0 then return end

    overlay.res_x = d.w
    overlay.res_y = d.h

    local base_scale = math.max(1.0, d.h / 1080)
    local scale = base_scale * (cfg.ui_scale or 1.0)

    local title_size    = math.floor(13 * scale)
    local subtitle_size = math.floor(11.5 * scale)
    local section_size  = math.floor(10.5 * scale)
    local row_size      = math.floor(11.5 * scale)

    local row_step      = math.floor(19.5 * scale)
    local section_step  = math.floor(18 * scale)
    local section_gap   = math.floor(10 * scale)

    local top_pad       = math.floor(16 * scale)
    local header_gap    = math.floor(8 * scale)
    local bottom_pad    = math.floor(20 * scale)
    local pad_x         = math.floor(18 * scale)
    local indent_x      = math.floor(8 * scale)

    local sections = params.sections or {}
    local total_rows = 0
    for _, sec in ipairs(sections) do
        total_rows = total_rows + #sec.items
    end

    local header_h = title_size + subtitle_size + math.floor(8 * scale)
    local sections_h = (#sections * section_step) + (math.max(0, #sections - 1) * section_gap) + (total_rows * row_step)
    local box_h = top_pad + header_h + header_gap + sections_h + bottom_pad
    
    -- Exactly 400px * scale (Matches video-monitor.lua column width 1:1)
    local box_w = math.floor((params.width or 400) * scale)

    -- Anchor to Bottom-Left corner, perfectly sharing the horizontal column with video-monitor
    local margin_x = math.floor(24 * scale)
    local margin_y = math.floor(24 * scale)
    local x1 = margin_x
    local x2 = x1 + box_w
    local y2 = d.h - margin_y
    local y1 = y2 - box_h

    -- Safety check: ensure card never clips above top boundary
    if y1 < margin_y then
        y1 = margin_y
        y2 = y1 + box_h
    end

    local ass = assdraw.ass_new()

    -- 0. Optional Backdrop Mask (Used by Crop Page)
    if params.extra_draw then
        params.extra_draw(ass, d, scale)
    end

    -- 1. Outer Translucent Rounded Glass Container
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H0A0A0A&\\alpha&H%s&}", cfg.bg_alpha))
    ass:pos(0, 0)
    ass:draw_start()
    ass:round_rect_cw(x1, y1, x2, y2, 8 * scale)
    ass:draw_stop()

    -- 2. Top Accent Border (NVIDIA Green)
    ass:new_event()
    ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&\\alpha&H10&}", cfg.color_green))
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(x1, y1, x2, y1 + math.max(2, math.floor(2.5 * scale)))
    ass:draw_stop()

    -- 3. Header Title & Subtitle
    local cur_y = y1 + top_pad
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        x1 + pad_x, cur_y, cfg.font_face, title_size, cfg.color_green, params.title or "CLIP MAKER"))

    cur_y = cur_y + title_size + math.floor(4 * scale)
    ass:new_event()
    ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
        x1 + pad_x, cur_y, cfg.font_face, subtitle_size, cfg.color_white, truncate_string(params.subtitle or "", 38)))

    -- Subtle Horizontal Divider
    cur_y = cur_y + subtitle_size + math.floor(8 * scale)
    ass:new_event()
    ass:append("{\\an7\\bord0\\shad0\\c&HFFFFFF&\\alpha&HD0&}")
    ass:pos(0, 0)
    ass:draw_start()
    ass:rect_cw(x1 + pad_x, cur_y, x2 - pad_x, cur_y + 1)
    ass:draw_stop()

    cur_y = cur_y + math.floor(8 * scale)

    -- 4. Render Categorized Sections with Vector Diamond Headers
    local d_rad = math.max(3, math.floor(3.5 * scale))
    for s_idx, sec in ipairs(sections) do
        local d_cx = x1 + pad_x + d_rad
        local d_cy = cur_y + math.floor(section_size * 0.52)
        local text_x = x1 + pad_x + (d_rad * 2) + math.floor(6 * scale)

        -- Section Header Vector Diamond Icon
        ass:new_event()
        ass:append(string.format("{\\an7\\bord0\\shad0\\c&H%s&}", sec.title_color or cfg.color_green))
        ass:pos(0, 0)
        ass:draw_start()
        ass:move_to(d_cx, d_cy - d_rad)
        ass:line_to(d_cx + d_rad, d_cy)
        ass:line_to(d_cx, d_cy + d_rad)
        ass:line_to(d_cx - d_rad, d_cy)
        ass:draw_stop()

        -- Section Header Title Tag
        ass:new_event()
        ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
            text_x, cur_y, cfg.font_face, section_size, sec.title_color or cfg.color_green, sec.title))

        cur_y = cur_y + section_step

        -- Section Item Rows
        for _, item in ipairs(sec.items) do
            local label, val_text, val_color = item[1], item[2], item[3]

            -- Label (Left-aligned + Indented: \an7)
            ass:new_event()
            ass:append(string.format("{\\an7\\pos(%d,%d)\\fn%s\\b0\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x1 + pad_x + indent_x, cur_y, cfg.font_face, row_size, cfg.color_gray, label))

            -- Value (Right-aligned: \an9)
            ass:new_event()
            ass:append(string.format("{\\an9\\pos(%d,%d)\\fn%s\\b1\\fs%d\\c&H%s&\\bord1\\3c&H000000&\\shad1}%s", 
                x2 - pad_x, cur_y, cfg.font_face, row_size, val_color or cfg.color_white, val_text))

            cur_y = cur_y + row_step
        end

        if s_idx < #sections then
            cur_y = cur_y + section_gap
        end
    end

    overlay.data = ass.text
    overlay:update()
end

-- =========================================================================
-- Page Abstraction & Inter-Script State Synchronization
-- =========================================================================

local Page = {}
Page.__index = Page

function Page.new()
    return setmetatable({ visible = false, keybinds = {} }, Page)
end

function Page:add_keybinds()
    for key, fn in pairs(self.keybinds) do
        mp.add_forced_key_binding(key, "clip_" .. key, fn, { repeatable = true })
    end
end

function Page:remove_keybinds()
    for key in pairs(self.keybinds) do
        mp.remove_key_binding("clip_" .. key)
    end
end

function Page:show()
    if self.visible then return end
    self.visible = true
    active_page_count = active_page_count + 1
    
    -- Notify other scripts (e.g. bottom bar) that Clip Maker is active
    mp.set_property_native("user-data/clip-maker-active", true)

    self:add_keybinds()
    self:draw()
end

function Page:hide()
    if not self.visible then return end
    self.visible = false
    self:remove_keybinds()
    active_page_count = math.max(0, active_page_count - 1)

    -- Debounced release: prevents microsecond state flickering between page transitions
    mp.add_timeout(0.05, function()
        if active_page_count == 0 then
            mp.set_property_native("user-data/clip-maker-active", false)
            overlay:remove()
        end
    end)
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
    local d = get_video_dimensions()
    if not d then return end

    local r = Region.new()
    r:set_from_points(self.pointA:to_screen(), self.pointB:to_screen())

    local rw = math.abs(self.pointA.x - self.pointB.x)
    local rh = math.abs(self.pointA.y - self.pointB.y)
    local ar_str = rh > 0 and string.format("%.2f:1", rw / rh) or "N/A"

    local sections = {
        {
            title = "COORDINATES",
            title_color = cfg.color_green,
            items = {
                { "[1] Top-Left", string.format("%d, %d", self.pointA.x, self.pointA.y), cfg.color_cyan },
                { "[2] Bottom-Right", string.format("%d, %d", self.pointB.x, self.pointB.y), cfg.color_cyan },
                { "Resolution", string.format("%dx%d (%s)", rw, rh, ar_str), cfg.color_yellow }
            }
        },
        {
            title = "CONTROLS",
            title_color = cfg.color_green,
            items = {
                { "[r] Reset", "Fullscreen", cfg.color_white },
                { "[ENTER] Apply", "Confirm Region", cfg.color_green },
                { "[ESC] Cancel", "Abort Selection", cfg.color_red }
            }
        }
    }

    render_glass_card({
        title = "CROP REGION SELECTOR",
        subtitle = "Interactive Geometry Cutter",
        width = 400,
        sections = sections,
        extra_draw = function(ass)
            -- Draw perimeter shadow mask outside crop box
            ass:new_event()
            ass:append("{\\an7\\bord0\\shad0\\c&H000000&\\alpha&H77&}")
            ass:pos(0, 0)
            ass:draw_start()
            ass:rect_cw(d.top_left.x, d.top_left.y, r.x, r.y + r.h)
            ass:rect_cw(r.x, d.top_left.y, d.bottom_right.x, r.y)
            ass:rect_cw(d.top_left.x, r.y + r.h, r.x + r.w, d.bottom_right.y)
            ass:rect_cw(r.x + r.w, r.y, d.bottom_right.x, d.bottom_right.y)
            ass:draw_stop()
        end
    })
end

-- =========================================================================
-- Options Interface
-- =========================================================================

local OptionItem = {}
OptionItem.__index = OptionItem

function OptionItem.new(optType, text, value, item_cfg, visible_fn)
    return setmetatable({
        optType = optType,
        text = text,
        value = value,
        cfg = item_cfg or {},
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
        return self.value and "YES" or "NO"
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
        { "p1", "p1 (Fastest / Low Quality)" },
        { "p2", "p2 (Faster)" },
        { "p3", "p3 (Fast)" },
        { "p4", "p4 (Balanced Default)" },
        { "p5", "p5 (Slow / High Quality)" },
        { "p6", "p6 (High Quality RTX)" },
        { "p7", "p7 (Highest Quality)" }
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
        { "burn_subtitles", OptionItem.new("bool", "Burn Active Subtitles", options.burn_subtitles) },
        { "nvenc_preset", OptionItem.new("list", "NVENC Preset", options.nvenc_preset, { values = nvenc_presets }, function()
            return formats[options.output_format].isNvenc
        end) },
        { "target_filesize", OptionItem.new("int", "Target Filesize", options.target_filesize, { step = 2500, min = 0, labels = { [0] = "Constant Quality (CQ Mode)" } }) },
        { "crf", OptionItem.new("int", "CQ / QP Quality", options.crf, { step = 1, min = 0, max = 51 }) },
        { "scale_height", OptionItem.new("list", "Scale Output Height", options.scale_height, { values = scale_opts }) },
        { "fps", OptionItem.new("list", "Framerate", options.fps, { values = fps_opts }) }
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
    local param_items = {}
    for i, item in ipairs(self.items) do
        local opt = item[2]
        if opt.visible_fn() then
            local is_sel = (self.selected == i)
            local prefix = is_sel and "▶ " or "   "
            local label_str = prefix .. opt.text
            local val_text = opt:get_display()
            local val_color = is_sel and cfg.color_cyan or cfg.color_white
            if opt.optType == "bool" then
                val_color = opt.value and cfg.color_green or cfg.color_yellow
            end
            table.insert(param_items, { label_str, val_text, val_color })
        end
    end

    local nav_items = {
        { "Navigate (▲ / ▼)", "Select Parameter", cfg.color_gray },
        { "Adjust (◀ / ▶)", "Change Value", cfg.color_cyan },
        { "[ENTER] Save", "Apply & Return", cfg.color_green },
        { "[ESC] Cancel", "Discard Changes", cfg.color_red }
    }

    local sections = {
        { title = "PARAMETERS", title_color = cfg.color_green, items = param_items },
        { title = "NAVIGATION", title_color = cfg.color_green, items = nav_items }
    }

    render_glass_card({
        title = "CLIP MAKER OPTIONS",
        subtitle = "Encoder, Quality & Resolution Settings",
        width = 400,
        sections = sections
    })
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
    local vf = mp.get_property_native("vf") or {}
    table.insert(vf, { name = "sub" })
    if self.region and self.region:is_valid() then
        local rw = self.region.w - (self.region.w % 2)
        local rh = self.region.h - (self.region.h % 2)
        local rx = self.region.x - (self.region.x % 2)
        local ry = self.region.y - (self.region.y % 2)
        table.insert(vf, {
            name = "crop",
            params = {
                w = tostring(rw),
                h = tostring(rh),
                x = tostring(rx),
                y = tostring(ry)
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
    local dur = (self.start_t >= 0 and self.end_t > self.start_t) and string.format("%.2fs", self.end_t - self.start_t) or "--"
    local crop_desc = (self.region and self.region:is_valid()) and string.format("%dx%d", self.region.w, self.region.h) or "Fullscreen"

    local sections = {
        {
            title = "PLAYBACK DETAILS",
            title_color = cfg.color_green,
            items = {
                { "Timeline Range", string.format("%s -> %s", format_time(self.start_t), format_time(self.end_t)), cfg.color_cyan },
                { "Active Duration", dur, cfg.color_yellow },
                { "Crop Geometry", crop_desc, cfg.color_white }
            }
        },
        {
            title = "CONTROLS",
            title_color = cfg.color_green,
            items = {
                { "[p] / [ESC]", "Exit Loop Preview", cfg.color_yellow }
            }
        }
    }

    render_glass_card({
        title = "CLIP PREVIEW (LOOP)",
        subtitle = "Active Viewport Audition",
        width = 400,
        sections = sections
    })
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
    local start_str = self.startTime >= 0 and format_time(self.startTime) or "Not Set"
    local end_str = self.endTime >= 0 and format_time(self.endTime) or "Not Set"
    local diff_str = (self.startTime >= 0 and self.endTime > self.startTime) and string.format("%.2fs", self.endTime - self.startTime) or "--"
    local fmt = formats[options.output_format]

    local crop_desc = self.region:is_valid() and string.format("%dx%d", self.region.w, self.region.h) or "Fullscreen"
    local media_name = mp.get_property("media-title") or mp.get_property("filename/no-ext") or "Active Media Stream"

    local rate_desc = options.target_filesize > 0 and string.format("%d kB Target", options.target_filesize) or string.format("CQ / CRF %d", options.crf)

    local sections = {
        {
            title = "TIMELINE",
            title_color = cfg.color_green,
            items = {
                { "[1] Start Marker", start_str .. "  [! Jump]", self.startTime >= 0 and cfg.color_cyan or cfg.color_gray },
                { "[2] End Marker", end_str .. "  [@ Jump]", self.endTime >= 0 and cfg.color_cyan or cfg.color_gray },
                { "Duration", diff_str, (self.startTime >= 0 and self.endTime > self.startTime) and cfg.color_yellow or cfg.color_gray }
            }
        },
        {
            title = "CONFIGURATION",
            title_color = cfg.color_green,
            items = {
                { "[c] Crop Frame", crop_desc, self.region:is_valid() and cfg.color_green or cfg.color_white },
                { "[o] Encoder Format", fmt.displayName, cfg.color_cyan },
                { "Quality Rate", rate_desc, cfg.color_white }
            }
        },
        {
            title = "EXECUTION",
            title_color = cfg.color_green,
            items = {
                { "[p] Loop Preview", "In-Player Playback", cfg.color_yellow },
                { "[e] Start Encode", "Launch Process", cfg.color_green },
                { "[ESC] Exit", "Close Clip Maker", cfg.color_gray }
            }
        }
    }

    render_glass_card({
        title = "CLIP MAKER",
        subtitle = media_name,
        width = 400,
        sections = sections
    })
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

    local filename = mp.get_property("filename", "clip")
    local filename_no_ext = mp.get_property("filename/no-ext", "clip")
    local s_str = seconds_to_path_element(start_t, false)
    local s_full = seconds_to_path_element(start_t, true)
    local e_str = seconds_to_path_element(end_t, false)
    local e_full = seconds_to_path_element(end_t, true)
    local m_tag = fmt.audioCodec ~= "" and "-audio" or ""

    local name = options.output_template
    name = name:gsub("%%f", function() return filename end)
    name = name:gsub("%%F", function() return filename_no_ext end)
    name = name:gsub("%%s", function() return s_str end)
    name = name:gsub("%%S", function() return s_full end)
    name = name:gsub("%%e", function() return e_str end)
    name = name:gsub("%%E", function() return e_full end)
    name = name:gsub("%%M", function() return m_tag end)
    name = name:gsub("[<>:\"/\\|?*]", "")

    return utils.join_path(dir, name .. "." .. fmt.outputExtension)
end

function MainPage:start_encode()
    if is_encoding then
        message("An encode is already in progress!", 3)
        return
    end

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

    -- Base command using dynamic portable binary resolution
    local cmd = {
        get_mpv_binary(),
        path,
        "--start=" .. format_time(self.startTime, false, true),
        "--end=" .. format_time(self.endTime, false, true),
        "--loop-file=no",
        "--no-pause",
        "--hwdec=no",
        "--audio-pitch-correction=no"
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

    -- Video Filter Pipeline
    local vf = {}

    -- Force 8-bit YUV420p for H.264 (Solves "10 bit encode not supported" on AV1 10-bit & HDR content)
    if fmt.forceYuv420 then
        table.insert(vf, "format=yuv420p")
    end

    -- Subtitle handling: burn if requested, otherwise strictly suppress raw muxing
    local current_sid = mp.get_property("sid")
    if options.burn_subtitles and mp.get_property_bool("sub-visibility", true) and current_sid and current_sid ~= "no" then
        table.insert(vf, "sub")
        table.insert(cmd, "--sid=" .. tostring(current_sid))
    else
        table.insert(cmd, "--sid=no")
    end

    -- Sanitize playback filters (strip d3d11vpp, VSR, and True HDR hardware filters)
    if options.apply_current_filters then
        local cur_vf = mp.get_property_native("vf") or {}
        for _, f in ipairs(cur_vf) do
            if f.enabled ~= false and f.name then
                local fn = f.name:lower()
                if not fn:find("d3d11") and not fn:find("vsr") and not fn:find("hdr") and not fn:find("sub") then
                    table.insert(vf, f.name)
                end
            end
        end
    end

    -- Force even dimensions to prevent NVENC/x264 "width/height not divisible by 2" errors
    if self.region:is_valid() then
        local rw = self.region.w - (self.region.w % 2)
        local rh = self.region.h - (self.region.h % 2)
        local rx = self.region.x - (self.region.x % 2)
        local ry = self.region.y - (self.region.y % 2)
        table.insert(vf, string.format("lavfi-crop=%d:%d:%d:%d", rw, rh, rx, ry))
    end

    if options.scale_height > 0 then
        local sh = options.scale_height - (options.scale_height % 2)
        table.insert(vf, "lavfi-scale=-2:" .. tostring(sh))
    end

    if options.fps > 0 then
        table.insert(vf, "fps=" .. tostring(options.fps))
    end

    for _, filter in ipairs(vf) do
        table.insert(cmd, "--vf-add=" .. filter)
    end

    -- Rate Control & NVENC Hardware Stability Settings
    if fmt.isNvenc then
        -- CRUCIAL: bf=0 prevents MP4 muxer crash: "pts < dts in stream 0 [encode] Writing packet failed"
        table.insert(cmd, "--ovcopts-add=bf=0")
        table.insert(cmd, "--ovcopts-add=preset=" .. options.nvenc_preset)

        if options.target_filesize <= 0 then
            table.insert(cmd, "--ovcopts-add=cq=" .. tostring(options.crf))
        else
            local total_kbits = options.target_filesize * 8
            local audio_kbits = (fmt.audioCodec ~= "") and (duration * options.strict_audio_bitrate) or 0
            local video_br = math.max(64, math.floor((total_kbits - audio_kbits) / duration))
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

    cmd = fmt:postCommandModifier(cmd, self.region, self.startTime, self.endTime)
    table.insert(cmd, "--o=" .. out_path)

    msg.info("Starting encode: " .. table.concat(cmd, " "))
    message("Encoding with " .. fmt.displayName .. "...", 3)
    is_encoding = true

    -- Non-blocking asynchronous subprocess (never freezes MPV's GUI)
    mp.command_native_async({
        name = "subprocess",
        args = cmd,
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, res, err)
        is_encoding = false
        if success and res and res.status == 0 then
            message("Encode Finished! Saved to:\n" .. out_path, 5)
        else
            local err_output = (res and (res.stdout or res.stderr)) or err or ""
            msg.error("Encode failed with status: " .. tostring(res and res.status or -1))
            if err_output ~= "" then msg.error("Output:\n" .. err_output) end

            local detected_err = ""
            for line in err_output:gmatch("[^\r\n]+") do
                local l = line:lower()
                if l:find("error") or l:find("failed") or l:find("cannot") or l:find("invalid") then
                    detected_err = line
                    break
                end
            end
            if detected_err == "" then
                detected_err = "Process exited with code " .. tostring(res and res.status or -1)
            end
            message("Encode Failed!\n" .. detected_err, 6)
        end
    end)
end

-- =========================================================================
-- Entrypoint & Keybinding
-- =========================================================================

local main = MainPage.new()

mp.add_key_binding(options.keybind, "display-clip-maker", function()
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