const std = @import("std");
const mem = std.mem;
const unicode = std.unicode;

const fcft = @import("fcft");
const pixman = @import("pixman");

const Buffer = @import("Buffer.zig");
const Bar = @import("Bar.zig");
const Tags = @import("Tags.zig");

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

const VisualBounds = struct {
    left: i32,
    width: i32,
};

fn visualBounds(glyphs: [*]*const fcft.Glyph, count: usize) VisualBounds {
    var left: i32 = std.math.maxInt(i32);
    var right: i32 = std.math.minInt(i32);
    var x: i32 = 0;

    for (glyphs[0..count]) |glyph| {
        const glyph_left = x + @as(i32, @intCast(glyph.x));
        left = @min(left, glyph_left);
        right = @max(right, glyph_left + @as(i32, @intCast(glyph.width)));
        x += @intCast(glyph.advance.x);
    }

    return .{ .left = left, .width = right - left };
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

fn clearImage(
    image: *pixman.Image,
    width: u16,
    height: u16,
    color: *pixman.Color,
) void {
    const rect = [_]pixman.Rectangle16{.{
        .x = 0,
        .y = 0,
        .width = width,
        .height = height,
    }};
    _ = pixman.Image.fillRectangles(.src, image, color, 1, &rect);
}

fn highlightTag(
    bar: *Bar,
    image: *pixman.Image,
    bounds: *std.ArrayList(Tags.Bounds),
    index: usize,
    alpha: u16,
) void {
    if (index >= bounds.items.len) return;
    fillTagHighlight(image, bounds.items[index], alpha, @intCast(bar.height));
}

fn fillTagHighlight(
    image: *pixman.Image,
    bounds: Tags.Bounds,
    alpha: u16,
    height: u16,
) void {
    const color = pixman.Color{
        .red = alpha,
        .green = alpha,
        .blue = alpha,
        .alpha = alpha,
    };
    const rect = [_]pixman.Rectangle16{.{
        .x = @intCast(bounds.left),
        .y = 0,
        .width = bounds.right - bounds.left,
        .height = height,
    }};

    _ = pixman.Image.fillRectangles(.over, image, &color, 1, &rect);
}

pub fn renderTags(bar: *Bar) !void {
    const surface = bar.tags.surface;
    const shm = state.wayland.shm.?;

    const tag_padding: i32 = 15;

    const Run = @typeInfo(@TypeOf(
        state.config.font.rasterizeTextRunUtf32(&[_]u32{}, .default),
    )).error_union.payload;

    const tags = bar.monitor.tags.list.items;
    const runs = try state.gpa.alloc(?Run, tags.len);
    const tag_widths = try state.gpa.alloc(i32, tags.len);
    defer {
        for (runs) |*run| {
            if (run.*) |value| value.*.destroy();
        }
        state.gpa.free(runs);
        state.gpa.free(tag_widths);
    }

    for (tags, 0..) |tag, index| {
        runs[index] = null;

        const runes = try toUtf8(state.gpa, tag.name);
        defer state.gpa.free(runes);

        if (runes.len == 0) continue;

        const run = try state.config.font.rasterizeTextRunUtf32(runes, .default);
        runs[index] = run;

        var run_width: i32 = 0;
        for (run.glyphs[0..run.count]) |glyph| {
            run_width += @intCast(glyph.advance.x);
        }
        tag_widths[index] = run_width;
    }

    var total_width: i32 = 0;
    const click_bounds = &bar.monitor.tags.click_bounds;
    try click_bounds.resize(state.gpa, runs.len);

    for (tag_widths, 0..) |width, index| {
        const box_width = width + tag_padding * 2;
        click_bounds.items[index] = .{
            .left = @intCast(total_width),
            .right = @intCast(total_width + box_width),
        };
        total_width += box_width;
    }

    bar.tags_width = @intCast(total_width);

    const buffers = &bar.tags.buffers;
    const buffer = Buffer.nextBuffer(
        buffers,
        shm,
        bar.tags_width,
        bar.height,
    ) catch |err| switch (err) {
        error.NoAvailableBuffers => return,
        else => return err,
    };
    if (buffer.buffer == null) return;
    buffer.busy = true;

    var bg_color = state.config.normalBgColor;
    clearImage(buffer.pix.?, bar.tags_width, bar.height, &bg_color);

    if (bar.monitor.tags.current) |index| {
        highlightTag(bar, buffer.pix.?, click_bounds, index, 0x3333);
    }

    if (bar.monitor.tags.hovered) |index| {
        if (bar.monitor.tags.current != index) {
            highlightTag(bar, buffer.pix.?, click_bounds, index, 0x4444);
        }
    }

    const fg_color = pixman.Image.createSolidFill(
        &state.config.normalFgColor,
    ).?;
    defer _ = fg_color.unref();

    for (runs, 0..) |maybe_run, index| {
        const run = maybe_run orelse continue;
        if (run.count == 0) continue;

        const bounds = click_bounds.items[index];
        const box_left: i32 = @intCast(bounds.left);
        const box_width: i32 =
            @as(i32, bounds.right) - box_left;

        const visual = visualBounds(run.glyphs, run.count);
        const visual_offset = @divTrunc(box_width - visual.width, 2);
        const start_x = box_left + visual_offset - visual.left;

        _ = try renderRun(
            start_x,
            buffer,
            fg_color,
            bar,
            run.glyphs,
            run.count,
        );
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, bar.tags_width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
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
    const trimmed = mem.trim(u8, text, " \r\n\x00");

    const cached_text = try state.gpa.dupe(u8, trimmed);
    if (bar.status_text) |old_text| state.gpa.free(old_text);
    bar.status_text = cached_text;

    const surface = bar.text.surface;
    const shm = state.wayland.shm.?;

    // utf8 encoding
    const runes = try toUtf8(state.gpa, trimmed);
    defer state.gpa.free(runes);

    // rasterize
    const font = state.config.font;
    const run = try font.rasterizeTextRunUtf32(runes, .default);
    defer run.destroy();

    // compute total width
    var status_width: u16 = 0;
    for (run.glyphs[0..run.count]) |glyph| {
        status_width += @intCast(glyph.advance.x);
    }

    // set subsurface offset
    const font_height: u32 = @intCast(state.config.font.height);
    const y_offset: i32 = @intCast(@divFloor(bar.height - font_height, 2));

    bar.tags.subsurface.setPosition(0, 0);
    bar.text.subsurface.setPosition(0, y_offset);

    const buffers = &bar.text.buffers;
    const buffer = try Buffer.nextBuffer(buffers, shm, bar.width, bar.height);
    if (buffer.buffer == null) return;
    buffer.busy = true;

    var bg_color = mem.zeroes(pixman.Color);
    clearImage(buffer.pix.?, bar.width, bar.height, &bg_color);

    const initial_x_status: i32 = if (bar.width > status_width + bar.text_padding)
        @intCast(bar.width - status_width - bar.text_padding)
    else
        0;

    var current_x: i32 = initial_x_status;
    bar.status_clicks.clearRetainingCapacity();

    const fg_color = pixman.Image.createSolidFill(&state.config.normalFgColor).?;
    defer _ = fg_color.unref();

    for (run.glyphs[0..run.count]) |glyph| {
        try bar.status_clicks.append(state.gpa, .{
            .left = current_x,
            .right = current_x + @as(i32, @intCast(glyph.advance.x)),
            .rune = glyph.cp,
        });

        const y = state.config.font.ascent - @as(i32, @intCast(glyph.y));

        pixman.Image.composite32(
            .over,
            fg_color,
            glyph.pix,
            buffer.pix.?,
            0,
            0,
            0,
            0,
            current_x,
            y,
            glyph.width,
            glyph.height,
        );

        current_x += @as(i32, @intCast(glyph.advance.x));
    }

    surface.setBufferScale(bar.monitor.scale);
    surface.damageBuffer(0, 0, bar.width, bar.height);
    surface.attach(buffer.buffer, 0, 0);
}
