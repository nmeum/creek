const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;
const zwlr = @import("wayland").client.zwlr;

const Buffer = @import("Buffer.zig");
const Monitor = @import("Monitor.zig");
const render = @import("render.zig");
const Widget = @import("Widget.zig");
const Bar = @This();

monitor: *Monitor,

layerSurface: *zwlr.LayerSurfaceV1,
background: struct {
    surface: *wl.Surface,
    viewport: *wp.Viewport,
    buffer: Buffer,
},

tags: Widget,
clock: Widget,
modules: Widget,

configured: bool,
width: u16,
height: u16,

pub fn create(monitor: *Monitor) !*Bar {
    const state = monitor.state;
    const globals = &state.wayland.globals;

    const self = try state.gpa.create(Bar);
    self.monitor = monitor;
    self.configured = false;

    self.background.surface = try globals.compositor.createSurface();
    self.background.viewport = try globals.viewporter.getViewport(self.background.surface);
    try self.background.buffer.resize(globals.shm, 1, 1);
    if (self.background.buffer.data) |data| data[0] = 0xff000000 else unreachable;

    self.layerSurface = try globals.layerShell.getLayerSurface(
        self.background.surface,
        monitor.output,
        .top,
        "levee",
    );

    self.tags = try Widget.init(state, self.background.surface);
    self.clock = try Widget.init(state, self.background.surface);
    self.modules = try Widget.init(state, self.background.surface);

    // setup layer surface
    self.layerSurface.setSize(0, state.config.height);
    self.layerSurface.setAnchor(
        .{ .top = true, .left = true, .right = true, .bottom = false },
    );
    self.layerSurface.setExclusiveZone(state.config.height);
    self.layerSurface.setMargin(0, 0, 0, 0);
    self.layerSurface.setListener(*Bar, layerSurfaceListener, self);

    self.tags.surface.commit();
    self.clock.surface.commit();
    self.modules.surface.commit();
    self.background.surface.commit();

    return self;
}

pub fn destroy(self: *Bar) void {
    self.monitor.bar = null;

    self.background.surface.destroy();
    self.layerSurface.destroy();
    self.background.buffer.deinit();

    self.tags.deinit();
    self.clock.deinit();
    self.modules.deinit();

    self.monitor.state.gpa.destroy(self);
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
            bg.surface.attach(bg.buffer.buffer, 0, 0);
            bg.surface.damageBuffer(0, 0, bar.width, bar.height);
            bg.viewport.setDestination(bar.width, bar.height);

            render.renderTags(bar) catch return;
            render.renderClock(bar) catch return;
            render.renderModules(bar) catch return;

            bar.tags.surface.commit();
            bar.clock.surface.commit();
            bar.modules.surface.commit();
            bar.background.surface.commit();
        },
        .closed => bar.destroy(),
    }
}
