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
