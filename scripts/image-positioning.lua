local opts = {
    drag_to_pan_margin = 50,
    drag_to_pan_move_if_full_view=false,
    cursor_centric_zoom_margin = 50,
    cursor_centric_zoom_auto_center = true,
    cursor_centric_zoom_dezoom_if_full_view = false,
}
local options = require 'mp.options'
local msg = require 'mp.msg'
local assdraw = require 'mp.assdraw'

options.read_options(opts, nil, function() end)

function clamp(value, low, high)
    if value <= low then
        return low
    elseif value >= high then
        return high
    else
        return value
    end
end


local cleanup = nil

function drag_to_pan_handler(table)
    if cleanup then
        cleanup()
        cleanup = nil
    end
    if table["event"] == "down" then
        local dim = mp.get_property_native("osd-dimensions")
        if not dim then return end
        local mouse_pos_origin, video_pan_origin = {}, {}
        local moved = false
        mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
        video_pan_origin[1] = mp.get_property_number("video-pan-x")
        video_pan_origin[2] = mp.get_property_number("video-pan-y")
        local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }
        local margin = opts.drag_to_pan_margin
        local move_up = true
        local move_lateral = true
        if not opts.drag_to_pan_move_if_full_view then
            if dim.ml >= 0 and dim.mr >= 0 then
                move_lateral = false
            end
            if dim.mt >= 0 and dim.mb >= 0 then
                move_up = false
            end
        end
        if not move_up and not move_lateral then return end
        local idle = function()
            if moved then
                local mX, mY = mp.get_mouse_pos()
                local pX = video_pan_origin[1]
                local pY = video_pan_origin[2]
                if move_lateral then
                    pX = video_pan_origin[1] + (mX - mouse_pos_origin[1]) / video_size[1]
                    if 2 * margin > dim.ml + dim.mr then
                        pX = clamp(pX,
                            (-margin + dim.w / 2) / video_size[1] - 0.5,
                            (margin - dim.w / 2) / video_size[1] + 0.5)
                    else
                        pX = clamp(pX,
                            (margin - dim.w / 2) / video_size[1] + 0.5,
                            (-margin + dim.w / 2) / video_size[1] - 0.5)
                    end
                end
                if move_up then
                    pY = video_pan_origin[2] + (mY - mouse_pos_origin[2]) / video_size[2]
                    if 2 * margin > dim.mt + dim.mb then
                        pY = clamp(pY,
                            (-margin + dim.h / 2) / video_size[2] - 0.5,
                            (margin - dim.h / 2) / video_size[2] + 0.5)
                    else
                        pY = clamp(pY,
                            (margin - dim.h / 2) / video_size[2] + 0.5,
                            (-margin + dim.h / 2) / video_size[2] - 0.5)
                    end
                end
                mp.command("no-osd set video-pan-x " .. clamp(pX, -3, 3) .. "; no-osd set video-pan-y " .. clamp(pY, -3, 3))
                moved = false
            end
        end
        mp.register_idle(idle)
        mp.add_forced_key_binding("mouse_move", "image-viewer-mouse-move", function() moved = true end)
        cleanup = function()
            mp.remove_key_binding("image-viewer-mouse-move")
            mp.unregister_idle(idle)
        end
    end
end


function cursor_centric_zoom_handler(amt)
    local zoom_inc = tonumber(amt)
    if not zoom_inc or zoom_inc == 0 then return end
    local dim = mp.get_property_native("osd-dimensions")
    if not dim then return end

    local margin = opts.cursor_centric_zoom_margin

    local video_size = { dim.w - dim.ml - dim.mr, dim.h - dim.mt - dim.mb }

    -- the size in pixels of the (in|de)crement
    local diff_width  = (2 ^ zoom_inc - 1) * video_size[1]
    local diff_height = (2 ^ zoom_inc - 1) * video_size[2]
    if not opts.cursor_centric_zoom_dezoom_if_full_view and
        zoom_inc < 0 and
        video_size[1] + diff_width + 2 * margin <= dim.w and
        video_size[2] + diff_height + 2 * margin <= dim.h
    then
        -- the zoom decrement is too much, reduce it such that the full image is visible, no more, no less
        -- in addition, this should take care of trying too zoom out while everything is already visible
        local new_zoom_inc_x = math.log((dim.w - 2 * margin) / video_size[1]) / math.log(2)
        local new_zoom_inc_y = math.log((dim.h - 2 * margin) / video_size[2]) / math.log(2)
        local new_zoom_inc = math.min(0, math.min(new_zoom_inc_x, new_zoom_inc_y))
        zoom_inc = new_zoom_inc
        diff_width  = (2 ^ zoom_inc - 1) * video_size[1]
        diff_height = (2 ^ zoom_inc - 1) * video_size[2]
    end
    local new_width = video_size[1] + diff_width
    local new_height = video_size[2] + diff_height

    local mouse_pos_origin = {}
    mouse_pos_origin[1], mouse_pos_origin[2] = mp.get_mouse_pos()
    local new_pan_x, new_pan_y

    -- some additional constraints:
    -- if image can be fully visible (in either direction), set pan to 0
    -- if border would show on either side, then prefer adjusting the pan even if not cursor-centric
    local auto_c = opts.cursor_centric_zoom_auto_center
    if auto_c and video_size[1] + diff_width + 2 * margin <= dim.w then
        new_pan_x = 0
    else
        local pan_x = mp.get_property("video-pan-x")
        local rx = (dim.ml + video_size[1] / 2 - mouse_pos_origin[1]) / (video_size[1] / 2)
        new_pan_x = (pan_x * video_size[1] + rx * diff_width / 2) / new_width
        if auto_c then
            new_pan_x = clamp(new_pan_x, (dim.w - 2 * margin) / (2 * new_width) - 0.5, - (dim.w - 2 * margin) / (2 * new_width) + 0.5)
        end
    end

    if auto_c and video_size[2] + diff_height + 2 * margin <= dim.h then
        new_pan_y = 0
    else
        local pan_y = mp.get_property("video-pan-y")
        local ry = (dim.mt + video_size[2] / 2 - mouse_pos_origin[2]) / (video_size[2] / 2)
        new_pan_y = (pan_y * video_size[2] + ry * diff_height / 2) / new_height
        if auto_c then
            new_pan_y = clamp(new_pan_y, (dim.h - 2 * margin) / (2 * new_height) - 0.5, - (dim.h - 2 * margin) / (2 * new_height) + 0.5)
        end
    end

    local zoom_origin = mp.get_property("video-zoom")
    mp.command("no-osd set video-zoom " .. zoom_origin + zoom_inc .. "; no-osd set video-pan-x " .. clamp(new_pan_x, -3, 3) .. "; no-osd set video-pan-y " .. clamp(new_pan_y, -3, 3))
end



mp.add_key_binding(nil, "drag-to-pan", drag_to_pan_handler, {complex = true})
mp.add_key_binding(nil, "cursor-centric-zoom", cursor_centric_zoom_handler)