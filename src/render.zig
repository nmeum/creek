const std = @import("std");
const mem = std.mem;

const cTime = @cImport(@cInclude("time.h"));
const fcft = @import("fcft");
const pixman = @import("pixman");

const Buffer = @import("shm.zig").Buffer;
const State = @import("main.zig").State;
const Surface = @import("wayland.zig").Surface;
const Tag = @import("tags.zig").Tag;
const Tags = @import("tags.zig").Tags;

pub fn renderBackground(surface: *Surface) !void {
    const state = surface.output.state;
    const wlSurface = surface.backgroundSurface;

    const buffer = try Buffer.nextBuffer(
        &surface.backgroundBuffers,
        state.wayland.shm,
        surface.width,
        surface.height,
    );
    buffer.busy = true;

    const area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
    };
    const color = &state.config.backgroundColor;
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, color, 1, &area);

    wlSurface.setBufferScale(surface.output.scale);
    wlSurface.damageBuffer(0, 0, surface.width, surface.height);
    wlSurface.attach(buffer.buffer, 0, 0);
}

pub fn renderTags(surface: *Surface) !void {
    const state = surface.output.state;
    const wlSurface = surface.tagsSurface;
    const tags = surface.output.tags.tags;

    const buffer = try Buffer.nextBuffer(
        &surface.tagsBuffers,
        surface.output.state.wayland.shm,
        surface.width,
        surface.height,
    );
    buffer.busy = true;

    for (tags) |*tag, i| {
        const offset = @intCast(i16, surface.height * i);
        try renderTag(buffer.pix.?, tag, surface.height, offset, state);
    }

    wlSurface.setBufferScale(surface.output.scale);
    wlSurface.damageBuffer(0, 0, surface.width, surface.height);
    wlSurface.attach(buffer.buffer, 0, 0);
}

pub fn renderClock(surface: *Surface) !void {
    const state = surface.output.state;
    const wlSurface = surface.clockSurface;

    const buffer = try Buffer.nextBuffer(
        &surface.clockBuffers,
        surface.output.state.wayland.shm,
        surface.width,
        surface.height,
    );
    buffer.busy = true;

    // clear the buffer
    const bg_area = [_]pixman.Rectangle16{
        .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
    };
    const bg_color = mem.zeroes(pixman.Color);
    _ = pixman.Image.fillRectangles(.src, buffer.pix.?, &bg_color, 1, &bg_area);

    // get formatted datetime
    const str = try formatDatetime(state);
    defer state.allocator.free(str);

    // convert chars to ints for fcft
    const cint = try state.allocator.alloc(c_int, str.len);
    defer state.allocator.free(cint);
    for (str) |char, i| cint[i] = char;

    const run = try fcft.TextRun.rasterize(state.config.font, cint, .default);
    defer run.destroy();

    var i: usize = 0;
    var text_width: u32 = 0;
    while (i < run.count) : (i += 1) {
        text_width += @intCast(u32, run.glyphs[i].advance.x);
    }

    const font_height = @intCast(u32, state.config.font.height);
    var x_offset = @intCast(i32, @divFloor(surface.width - text_width, 2));
    var y_offset = @intCast(i32, @divFloor(surface.height - font_height, 2));

    i = 0;
    var color = pixman.Image.createSolidFill(&state.config.foregroundColor).?;
    while (i < run.count) : (i += 1) {
        const glyph = run.glyphs[i];
        const x = x_offset + @intCast(i32, glyph.x);
        const y = y_offset + state.config.font.ascent - @intCast(i32, glyph.y);
        pixman.Image.composite32(
            .over,
            color,
            glyph.pix,
            buffer.pix.?,
            0, 0, 0, 0,
            x, y,
            glyph.width, glyph.height,
        );
        x_offset += glyph.advance.x;
    }

    wlSurface.setBufferScale(surface.output.scale);
    wlSurface.damageBuffer(0, 0, surface.width, surface.height);
    wlSurface.attach(buffer.buffer, 0, 0);
}

fn renderTag(
    pix: *pixman.Image,
    tag: *const Tag,
    height: u16,
    offset: i16,
    state: *State,
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
    const glyph = try fcft.Glyph.rasterize(font, tag.label, .default);
    const x = offset + @divFloor(size - glyph.width, 2);
    const y = @divFloor(size - glyph.height, 2);
    pixman.Image.composite32(
        .over,
        char,
        glyph.pix,
        pix,
        0, 0, 0, 0,
        x, y,
        glyph.width, glyph.height,
    );
}

fn formatDatetime(state: *State) ![]const u8 {
    var buf = try state.allocator.alloc(u8, 256);
    const now = cTime.time(null);
    const local = cTime.localtime(&now);
    const len = cTime.strftime(
        buf.ptr,
        buf.len,
        state.config.clockFormat,
        local,
    );
    return state.allocator.resize(buf, len).?;
}
