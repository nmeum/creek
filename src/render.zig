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

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}

pub fn renderText(bar: *Bar, text: []u8) !void {
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
    if (!tag.focused and tag.occupied) {
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
