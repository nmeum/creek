const std = @import("std");
const mem = std.mem;

const fcft = @import("fcft");
const pixman = @import("pixman");
const time = @cImport(@cInclude("time.h"));

const Buffer = @import("Buffer.zig");
const Bar = @import("Bar.zig");
const Tag = @import("Tags.zig").Tag;
const utils = @import("utils.zig");

const Backlight = @import("modules/Backlight.zig");
const Battery = @import("modules/Battery.zig");
const Pulse = @import("modules/Pulse.zig");

const state = &@import("root").state;

pub const RenderFn = fn (*Bar) anyerror!void;

pub fn renderTags(bar: *Bar) !void {
    const surface = bar.tags.surface;
    const tags = bar.monitor.tags.tags;

    const width = bar.height * 9;
    const buffer = try Buffer.nextBuffer(
        &bar.tags.buffers,
        state.wayland.globals.shm,
        width,
        bar.height,
    );
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

pub fn renderClock(bar: *Bar) !void {
    const surface = bar.clock.surface;
    const shm = state.wayland.globals.shm;

    // utf8 datetime
    const str = try formatDatetime();
    defer state.gpa.free(str);
    const runes = try utils.toUtf8(state.gpa, str);
    defer state.gpa.free(runes);

    // resterize
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
    const font_height = @intCast(u32, font.height);
    const x_offset = @intCast(i32, (bar.width - width) / 2);
    const y_offset = @intCast(i32, (bar.height - font_height) / 2);
    bar.clock.subsurface.setPosition(x_offset, y_offset);

    const buffers = &bar.clock.buffers;
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
    var color = pixman.Image.createSolidFill(&state.config.foregroundColor).?;
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

pub fn renderModules(bar: *Bar) !void {
    const surface = bar.modules.surface;
    const shm = state.wayland.globals.shm;

    // compose string
    var string = std.ArrayList(u8).init(state.gpa);
    defer string.deinit();

    const writer = string.writer();
    for (state.modules.order.items) |tag| {
        try writer.print(" | ", .{});
        switch (tag) {
            .backlight => try state.modules.backlight.?.print(writer),
            .battery => try state.modules.battery.?.print(writer),
            .pulse => try state.modules.pulse.?.print(writer),
        }
    }

    // ut8 encoding
    const runes = try utils.toUtf8(state.gpa, string.items);
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
    var x_offset = @intCast(i32, bar.width - width);
    var y_offset = @intCast(i32, @divFloor(bar.height - font_height, 2));
    bar.modules.subsurface.setPosition(x_offset, y_offset);

    const buffers = &bar.modules.buffers;
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
    var color = pixman.Image.createSolidFill(&state.config.foregroundColor).?;
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
    const outer_color = if (tag.focused or tag.occupied) blk: {
        break :blk &state.config.foregroundColor;
    } else blk: {
        break :blk &state.config.backgroundColor;
    };
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
    const inner_color = &state.config.backgroundColor;
    if (!tag.focused and tag.occupied) {
        _ = pixman.Image.fillRectangles(.over, pix, inner_color, 1, &inner);
    }

    const glyph_color = if (tag.focused) blk: {
        break :blk &state.config.backgroundColor;
    } else blk: {
        break :blk &state.config.foregroundColor;
    };
    const font = state.config.font;
    var char = pixman.Image.createSolidFill(glyph_color).?;
    const glyph = try font.rasterizeCharUtf32(tag.label, .default);
    const x = offset + @divFloor(size - glyph.width, 2);
    const y = @divFloor(size - glyph.height, 2);
    pixman.Image.composite32(.over, char, glyph.pix, pix, 0, 0, 0, 0, x, y, glyph.width, glyph.height);
}

fn formatDatetime() ![]const u8 {
    var buf = try state.gpa.alloc(u8, 256);
    const now = time.time(null);
    const local = time.localtime(&now);
    const len = time.strftime(
        buf.ptr,
        buf.len,
        state.config.clockFormat,
        local,
    );
    return state.gpa.resize(buf, len).?;
}
