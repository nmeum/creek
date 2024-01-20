const std = @import("std");
const mem = std.mem;

const fcft = @import("fcft");
const pixman = @import("pixman");
const time = @cImport(@cInclude("time.h"));

const Buffer = @import("Buffer.zig");
const Bar = @import("Bar.zig");
const Tag = @import("Tags.zig").Tag;
const utils = @import("utils.zig");

const state = &@import("root").state;

pub const RenderFn = fn (*Bar) anyerror!void;

pub fn renderTags(bar: *Bar) !void {
    const surface = bar.tags.surface;
    const tags = bar.monitor.tags.tags;

    const buffers = &bar.tags.buffers;
    const shm = state.wayland.shm.?;

    const width = bar.height * 9;
    const buffer = try Buffer.nextBuffer(buffers, shm, width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    for (tags) |*tag, i| {
        const offset = @intCast(i16, bar.height * i);
        try renderTag(buffer.pix.?, tag, bar.height, offset);
    }

    bar.tags_width = width;
    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

fn renderRun(start: i32, buffer: *Buffer, image: *pixman.Image, bar: *Bar, glyphs: [*]*const fcft.Glyph, count: usize) !i32 {
    const font_height = @intCast(u32, state.config.font.height);
    const y_offset: i32 = @intCast(i32, (bar.height - font_height) / 2);

    var i: usize = 0;
    var x: i32 = start;
    while (i < count) : (i += 1) {
        const glyph = glyphs[i];
        x += @intCast(i32, glyph.x);
        const y = (state.config.font.ascent - @intCast(i32, glyph.y)) + y_offset;
        pixman.Image.composite32(.over, image, glyph.pix, buffer.pix.?, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
        x += glyph.advance.x - @intCast(i32, glyph.x);
    }

    return x;
}

pub fn renderTitle(bar: *Bar, title: []const u8) !void {
    const surface = bar.title.surface;
    const shm = state.wayland.shm.?;

    const runes = try utils.toUtf8(state.gpa, title);
    defer state.gpa.free(runes);

    // resterize
    const font = state.config.font;
    const run = try font.rasterizeTextRunUtf32(runes, .default);
    defer run.destroy();

    // calculate width
    const title_start = bar.tags_width;
    const text_start = if (bar.text_width == 0) blk: {
        break :blk 0;
    } else blk: {
        break :blk bar.width - bar.text_width - bar.text_padding;
    };
    const width = if (text_start > 0) blk: {
        break :blk @intCast(u16, text_start - title_start - bar.text_padding);
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

    const bg_color = if (title.len == 0) blk: {
        break :blk state.config.normalBgColor;
    } else blk: {
        break :blk state.config.focusBgColor;
    };
    const bg_area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = width, .height = bar.height },
    };
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &bg_color, 1, &bg_area);

    // calculate maximum amount of glyphs that can be displayed
    var max_x: i32 = bar.text_padding;
    var max_glyphs: u16 = 0;
    var i: usize = 0;
    while (i < run.count) : (i += 1) {
        const glyph = run.glyphs[i];
        max_x += @intCast(i32, glyph.x);
        if (max_x >= width - (2 * bar.text_padding) - bar.abbrev_width) {
            break;
        }
        max_x += glyph.advance.x - @intCast(i32, glyph.x);
        max_glyphs += 1;
    }

    var x: i32 = bar.text_padding;
    var color = pixman.Image.createSolidFill(&state.config.focusFgColor).?;
    x += try renderRun(bar.text_padding, buffer, color, bar, run.glyphs, max_glyphs);
    if (run.count > max_glyphs) { // if abbreviated
        _ = try renderRun(x, buffer, color, bar, bar.abbrev_run.glyphs, bar.abbrev_run.count);
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

pub fn renderText(bar: *Bar, text: []const u8) !void {
    const surface = bar.text.surface;
    const shm = state.wayland.shm.?;

    // utf8 encoding
    const runes = try utils.toUtf8(state.gpa, text);
    defer state.gpa.free(runes);

    // rasterize
    const font = state.config.font;
    const run = try font.rasterizeTextRunUtf32(runes, .default);
    defer run.destroy();

    // compute total width
    var i: usize = 0;
    var width: u16 = 0;
    while (i < run.count) : (i += 1) {
        width += @intCast(u16, run.glyphs[i].advance.x);
    }

    // set subsurface offset
    const font_height = @intCast(u32, state.config.font.height);
    var x_offset = @intCast(i32, bar.width - width - bar.text_padding);
    var y_offset = @intCast(i32, @divFloor(bar.height - font_height, 2));
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
    var color = pixman.Image.createSolidFill(&state.config.normalFgColor).?;
    while (i < run.count) : (i += 1) {
        const glyph = run.glyphs[i];
        x += @intCast(i32, glyph.x);
        const y = state.config.font.ascent - @intCast(i32, glyph.y);
        pixman.Image.composite32(.over, color, glyph.pix, buffer.pix.?, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
        x += glyph.advance.x - @intCast(i32, glyph.x);
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);

    // render title again if text width changed
    if (width != bar.text_width) {
        bar.text_width = width;

        if (state.wayland.seat) |seat| {
            seat.mtx.lock();
            if (seat.window_title) |t| {
                renderTitle(bar, t) catch |err| {
                    seat.mtx.unlock();
                    return err;
                };
                bar.title.surface.commit();
                bar.background.surface.commit();
            }
            seat.mtx.unlock();
        }
    }
}

fn renderTag(
    pix: *pixman.Image,
    tag: *const Tag,
    height: u16,
    offset: i16,
) !void {
    const size = @intCast(u16, height);

    const outer = [_]pixman.Rectangle16{
        .{ .x = offset, .y = 0, .width = size, .height = size },
    };
    const outer_color = tag.outerColor();
    _ = pixman.Image.fillRectangles(.over, pix, outer_color, 1, &outer);

    const border = state.config.border;
    const inner = [_]pixman.Rectangle16{
        .{
            .x = offset + border,
            .y = border,
            .width = size - 2 * border,
            .height = size - 2 * border,
        },
    };
    const inner_color = &state.config.normalBgColor;
    if (!(tag.focused or tag.urgent) and tag.occupied) {
        _ = pixman.Image.fillRectangles(.over, pix, inner_color, 1, &inner);
    }

    const glyph_color = tag.glyphColor();
    const font = state.config.font;
    var char = pixman.Image.createSolidFill(glyph_color).?;
    const glyph = try font.rasterizeCharUtf32(tag.label, .default);
    const x = offset + @divFloor(size - glyph.width, 2);
    const y = @divFloor(size - glyph.height, 2);
    pixman.Image.composite32(.over, char, glyph.pix, pix, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
}
