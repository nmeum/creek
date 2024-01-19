const std = @import("std");
const log = std.log;
const mem = std.mem;

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

tags: Widget,
text: Widget,

configured: bool,
width: u16,
height: u16,

// Convert a pixman u16 color to a 32-bit color with a pre-multiplied
// alpha channel as used by the "Single-pixel buffer" Wayland protocol.
fn toRgba(color: u16) u32 {
    return (@as(u32, color) >> 8) << 24 | 0xffffff;
}

pub fn create(monitor: *Monitor) !*Bar {
    const bg_color = &state.config.backgroundColor;
    const self = try state.gpa.create(Bar);
    self.monitor = monitor;
    self.configured = false;

    const compositor = state.wayland.compositor.?;
    const viewporter = state.wayland.viewporter.?;
    const spb_manager = state.wayland.single_pixel_buffer_manager.?;
    const layer_shell = state.wayland.layer_shell.?;

    self.background.surface = try compositor.createSurface();
    self.background.viewport = try viewporter.getViewport(self.background.surface);
    self.background.buffer = try spb_manager.createU32RgbaBuffer(
        toRgba(bg_color.red),
        toRgba(bg_color.green),
        toRgba(bg_color.blue),
        0xffffffff
    );

    self.layer_surface = try layer_shell.getLayerSurface(self.background.surface, monitor.output, .top, "levee");

    self.tags = try Widget.init(self.background.surface);
    self.text = try Widget.init(self.background.surface);

    // setup layer surface
    self.layer_surface.setSize(0, state.config.height);
    self.layer_surface.setAnchor(
        .{ .top = true, .left = true, .right = true, .bottom = false },
    );
    self.layer_surface.setExclusiveZone(state.config.height);
    self.layer_surface.setMargin(0, 0, 0, 0);
    self.layer_surface.setListener(*Bar, layerSurfaceListener, self);

    self.tags.surface.commit();
    self.text.surface.commit();
    self.background.surface.commit();

    return self;
}

pub fn destroy(self: *Bar) void {
    self.monitor.bar = null;
    self.layer_surface.destroy();

    self.background.surface.destroy();
    self.background.viewport.destroy();
    self.background.buffer.destroy();

    self.tags.deinit();
    state.gpa.destroy(self);
}

fn layerSurfaceListener(
    layerSurface: *zwlr.LayerSurfaceV1,
    event: zwlr.LayerSurfaceV1.Event,
    bar: *Bar,
) void {
    switch (event) {
        .configure => |data| {
            bar.configured = true;
            bar.width = @intCast(u16, data.width);
            bar.height = @intCast(u16, data.height);

            layerSurface.ackConfigure(data.serial);

            const bg = &bar.background;
            bg.surface.attach(bg.buffer, 0, 0);
            bg.surface.damageBuffer(0, 0, bar.width, bar.height);
            bg.viewport.setDestination(bar.width, bar.height);

            render.renderTags(bar) catch |err| {
                log.err("renderTags failed for monitor {}: {s}",
                        .{bar.monitor.globalName, @errorName(err)});
                return;
            };

            bar.tags.surface.commit();
            bar.text.surface.commit();
            bar.background.surface.commit();
        },
        .closed => bar.destroy(),
    }
}
