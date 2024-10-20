const std = @import("std");
const log = std.log;
const mem = std.mem;

const fcft = @import("fcft");
const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;
const zwlr = @import("wayland").client.zwlr;

const Buffer = @import("Buffer.zig");
const Monitor = @import("Monitor.zig");
const render = @import("render.zig");
const Widget = @import("Widget.zig");
const Bar = @This();

const state = &@import("root").state;

monitor: *Monitor,

layer_surface: *zwlr.LayerSurfaceV1,
background: struct {
    surface: *wl.Surface,
    viewport: *wp.Viewport,
    buffer: *wl.Buffer,
},

title: Widget,
tags: Widget,
text: Widget,

tags_width: u16,
text_width: u16,

abbrev_width: u16,
abbrev_run: *const fcft.TextRun,

text_padding: i32,
configured: bool,
width: u16,
height: u16,

// Convert a pixman u16 color to a 32-bit color with a pre-multiplied
// alpha channel as used by the "Single-pixel buffer" Wayland protocol.
fn toRgba(color: u16) u32 {
    return (@as(u32, color) >> 8) << 24 | 0xffffff;
}

pub fn create(monitor: *Monitor) !*Bar {
    const bg_color = &state.config.normalBgColor;
    const self = try state.gpa.create(Bar);
    self.monitor = monitor;
    self.configured = false;

    const compositor = state.wayland.compositor.?;
    const viewporter = state.wayland.viewporter.?;
    const spb_manager = state.wayland.single_pixel_buffer_manager.?;
    const layer_shell = state.wayland.layer_shell.?;

    self.background.surface = try compositor.createSurface();
    self.background.viewport = try viewporter.getViewport(self.background.surface);
    self.background.buffer = try spb_manager.createU32RgbaBuffer(toRgba(bg_color.red), toRgba(bg_color.green), toRgba(bg_color.blue), 0xffffffff);

    self.layer_surface = try layer_shell.getLayerSurface(self.background.surface, monitor.output, .top, "creek");

    self.title = try Widget.init(self.background.surface);
    self.tags = try Widget.init(self.background.surface);
    self.text = try Widget.init(self.background.surface);

    // calculate right padding for status text
    const font = state.config.font;
    const char_run = try font.rasterizeTextRunUtf32(&[_]u32{' '}, .default);
    self.text_padding = char_run.glyphs[0].advance.x;
    char_run.destroy();

    // rasterize abbreviation glyphs for window ttile.
    self.abbrev_run = try font.rasterizeTextRunUtf32(&[_]u32{'…'}, .default);
    self.abbrev_width = 0;
    var i: usize = 0;
    while (i < self.abbrev_run.count) : (i += 1) {
        self.abbrev_width += @intCast(self.abbrev_run.glyphs[i].advance.x);
    }

    // setup layer surface
    self.layer_surface.setSize(0, state.config.height);
    self.layer_surface.setAnchor(
        .{ .top = true, .left = true, .right = true, .bottom = false },
    );
    self.layer_surface.setExclusiveZone(state.config.height);
    self.layer_surface.setMargin(0, 0, 0, 0);
    self.layer_surface.setListener(*Bar, layerSurfaceListener, self);

    self.tags.surface.commit();
    self.title.surface.commit();
    self.text.surface.commit();
    self.background.surface.commit();

    self.tags_width = 0;
    self.text_width = 0;

    return self;
}

pub fn destroy(self: *Bar) void {
    self.abbrev_run.destroy();
    self.monitor.bar = null;

    self.layer_surface.destroy();

    self.background.buffer.destroy();
    self.background.viewport.destroy();
    self.background.surface.destroy();

    self.title.deinit();
    self.tags.deinit();
    self.text.deinit();
    state.gpa.destroy(self);
}

fn layerSurfaceListener(
    layerSurface: *zwlr.LayerSurfaceV1,
    event: zwlr.LayerSurfaceV1.Event,
    bar: *Bar,
) void {
    switch (event) {
        .configure => |data| {
            layerSurface.ackConfigure(data.serial);

            const w: u16 = @intCast(data.width);
            const h: u16 = @intCast(data.height);
            if (bar.configured and bar.width == w and bar.height == h) {
                return;
            }

            bar.configured = true;
            bar.width = w;
            bar.height = h;

            const bg = &bar.background;
            bg.surface.attach(bg.buffer, 0, 0);
            bg.surface.damageBuffer(0, 0, bar.width, bar.height);
            bg.viewport.setDestination(bar.width, bar.height);

            render.renderTags(bar) catch |err| {
                log.err("renderTags failed for monitor {}: {s}", .{ bar.monitor.globalName, @errorName(err) });
                return;
            };

            bar.tags.surface.commit();
            bar.title.surface.commit();
            bar.text.surface.commit();
            bar.background.surface.commit();
        },
        .closed => bar.destroy(),
    }
}
