const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const fcft = @import("fcft");
const pixman = @import("pixman");
const time = @cImport(@cInclude("time.h"));

const Buffer = @import("Buffer.zig");
const Bar = @import("Bar.zig");
const Tag = @import("Tags.zig").Tag;

const state = &@import("root").state;

pub const RenderFn = fn (*Bar) anyerror!void;

pub fn toUtf8(gpa: mem.Allocator, bytes: []const u8) ![]u32 {
    const utf8 = try unicode.Utf8View.init(bytes);
    var iter = utf8.iterator();

    var runes = try std.ArrayList(u32).initCapacity(gpa, bytes.len);
    var i: usize = 0;
    while (iter.nextCodepoint()) |rune| : (i += 1) {
        runes.appendAssumeCapacity(rune);
    }

    return runes.toOwnedSlice(gpa);
}

pub fn renderTags(bar: *Bar) !void {
    const surface = bar.tags.surface;
    const tags = bar.monitor.tags.tags;

    const buffers = &bar.tags.buffers;
    const shm = state.wayland.shm.?;

    const width = bar.height * @as(u16, tags.len + 1);
    const buffer = try Buffer.nextBuffer(buffers, shm, width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    for (&tags, 0..) |*tag, i| {
        const offset: i16 = @intCast(bar.height * i);
        try renderTag(buffer.pix.?, tag, bar.height, offset);
    }

    // Separator tag to visually separate last focused tag from
    // focused window title (both use the same background color).
    const offset: i16 = @intCast(bar.height * tags.len);
    try renderTag(buffer.pix.?, &Tag{ .label = '|' }, bar.height, offset);

    bar.tags_width = width;
    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

fn renderRun(start: i32, buffer: *Buffer, image: *pixman.Image, bar: *Bar, glyphs: [*]*const fcft.Glyph, count: usize) !i32 {
    const font_height: u32 = @intCast(state.config.font.height);
    const y_offset: i32 = @intCast((bar.height - font_height) / 2);

    var i: usize = 0;
    var x: i32 = start;
    while (i < count) : (i += 1) {
        const glyph = glyphs[i];
        x += @intCast(glyph.x);
        const y = (state.config.font.ascent - @as(i32, @intCast(glyph.y))) + y_offset;
        pixman.Image.composite32(.over, image, glyph.pix, buffer.pix.?, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
        x += glyph.advance.x - @as(i32, @intCast(glyph.x));
    }

    return x;
}

pub fn renderTitle(bar: *Bar, title: ?[]const u8) !void {
    const surface = bar.title.surface;
    const shm = state.wayland.shm.?;

    var runes: ?[]u32 = null;
    if (title) |t| {
        if (t.len > 0)
            runes = try toUtf8(state.gpa, t);
    }
    defer {
        if (runes) |r| state.gpa.free(r);
    }

    // calculate width
    const title_start = bar.tags_width;
    const text_start = if (bar.text_width == 0) blk: {
        break :blk 0;
    } else blk: {
        break :blk bar.width - bar.text_width - bar.text_padding;
    };
    const width: u16 = if (text_start > 0) blk: {
        break :blk @intCast(text_start - title_start - bar.text_padding);
    } else blk: {
        break :blk bar.width - title_start;
    };

    // set subsurface offset
    const x_offset = bar.tags_width;
    const y_offset = 0;
    bar.title.subsurface.setPosition(x_offset, y_offset);

    const buffers = &bar.title.buffers;
    const buffer = try Buffer.nextBuffer(buffers, shm, width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    var bg_color = state.config.normalBgColor;
    if (title) |t| {
        if (t.len > 0) bg_color = state.config.focusBgColor;
    }
    const bg_area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = width, .height = bar.height },
    };
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &bg_color, 1, &bg_area);

    if (runes) |r| {
        const font = state.config.font;
        const run = try font.rasterizeTextRunUtf32(r, .default);
        defer run.destroy();

        // calculate maximum amount of glyphs that can be displayed
        var max_x: i32 = bar.text_padding;
        var max_glyphs: u16 = 0;
        var i: usize = 0;
        while (i < run.count) : (i += 1) {
            const glyph = run.glyphs[i];
            max_x += @intCast(glyph.x);
            if (max_x >= width - (2 * bar.text_padding) - bar.abbrev_width) {
                break;
            }
            max_x += glyph.advance.x - @as(i32, @intCast(glyph.x));
            max_glyphs += 1;
        }

        var x: i32 = bar.text_padding;
        const color = pixman.Image.createSolidFill(&state.config.focusFgColor).?;
        x += try renderRun(bar.text_padding, buffer, color, bar, run.glyphs, max_glyphs);
        if (run.count > max_glyphs) { // if abbreviated
            _ = try renderRun(x, buffer, color, bar, bar.abbrev_run.glyphs, bar.abbrev_run.count);
        }
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

pub fn resetText(bar: *Bar) !void {
    const surface = bar.text.surface;
    const shm = state.wayland.shm.?;

    const buffers = &bar.text.buffers;
    const buffer = try Buffer.nextBuffer(buffers, shm, bar.text_width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    const text_to_bottom: u16 =
        @intCast(state.config.font.height + bar.text_padding);
    const bg_area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = bar.text_width, .height = text_to_bottom },
    };
    var bg_color = state.config.normalBgColor;
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &bg_color, 1, &bg_area);

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, bar.text_width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

pub fn renderText(bar: *Bar, text: []const u8) !void {
    const surface = bar.text.surface;
    const shm = state.wayland.shm.?;

    // utf8 encoding
    const runes = try toUtf8(state.gpa, text);
    defer state.gpa.free(runes);

    // rasterize
    const font = state.config.font;
    const run = try font.rasterizeTextRunUtf32(runes, .default);
    defer run.destroy();

    // compute total width
    var i: usize = 0;
    var width: u16 = 0;
    while (i < run.count) : (i += 1) {
        width += @intCast(run.glyphs[i].advance.x);
    }

    // set subsurface offset
    const font_height: u32 = @intCast(state.config.font.height);
    const x_offset: i32 = @intCast(bar.width - width - bar.text_padding);
    const y_offset: i32 = @intCast(@divFloor(bar.height - font_height, 2));
    bar.text.subsurface.setPosition(x_offset, y_offset);

    const buffers = &bar.text.buffers;
    const buffer = try Buffer.nextBuffer(buffers, shm, width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    const bg_area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = width, .height = bar.height },
    };
    const bg_color = mem.zeroes(pixman.Color);
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &bg_color, 1, &bg_area);

    var x: i32 = 0;
    i = 0;
    const color = pixman.Image.createSolidFill(&state.config.normalFgColor).?;
    while (i < run.count) : (i += 1) {
        const glyph = run.glyphs[i];
        x += @intCast(glyph.x);
        const y = state.config.font.ascent - @as(i32, @intCast(glyph.y));
        pixman.Image.composite32(.over, color, glyph.pix, buffer.pix.?, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
        x += glyph.advance.x - @as(i32, @intCast(glyph.x));
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);

    // render title again if text width changed
    if (width != bar.text_width) {
        bar.text_width = width;

        if (state.wayland.river_seat) |seat| {
            seat.mtx.lock();
            defer seat.mtx.unlock();

            try renderTitle(bar, seat.window_title);
            bar.title.surface.commit();
            bar.background.surface.commit();
        }
    }
}

fn renderTag(
    pix: *pixman.Image,
    tag: *const Tag,
    size: u16,
    offset: i16,
) !void {
    const outer = [_]pixman.Rectangle16{
        .{ .x = offset, .y = 0, .width = size, .height = size },
    };
    const outer_color = tag.bgColor();
    _ = pixman.Image.fillRectangles(.over, pix, outer_color, 1, &outer);

    if (tag.occupied) {
        const font_height: u16 = @intCast(state.config.font.height);

        // Constants taken from dwm-6.3 drawbar function.
        const boxs: i16 = @intCast(font_height / 9);
        const boxw: u16 = font_height / 6 + 2;

        const box = pixman.Rectangle16{
            .x = offset + boxs,
            .y = boxs,
            .width = boxw,
            .height = boxw,
        };

        const box_color = if (tag.focused) blk: {
            break :blk &state.config.normalBgColor;
        } else blk: {
            break :blk tag.fgColor();
        };

        _ = pixman.Image.fillRectangles(.over, pix, box_color, 1, &[_]pixman.Rectangle16{box});
        if (!tag.focused) {
            const border = 1; // size of the border
            const inner = pixman.Rectangle16{
                .x = box.x + border,
                .y = box.y + border,
                .width = box.width - (2 * border),
                .height = box.height - (2 * border),
            };

            const inner_color = tag.bgColor();
            _ = pixman.Image.fillRectangles(.over, pix, inner_color, 1, &[_]pixman.Rectangle16{inner});
        }
    }

    const glyph_color = tag.fgColor();
    const font = state.config.font;
    const char = pixman.Image.createSolidFill(glyph_color).?;
    const glyph = try font.rasterizeCharUtf32(tag.label, .default);
    const x = offset + @divFloor(size - glyph.width, 2);
    const y = @divFloor(size - glyph.height, 2);
    pixman.Image.composite32(.over, char, glyph.pix, pix, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
}
