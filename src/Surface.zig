const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;

const Buffer = @import("Buffer.zig");
const Monitor = @import("wayland.zig").Monitor;
const render = @import("render.zig");
const Surface = @This();

monitor: *Monitor,

backgroundSurface: *wl.Surface,
layerSurface: *zwlr.LayerSurfaceV1,
backgroundBuffers: [2]Buffer,

tagsSurface: *wl.Surface,
tagsSubsurface: *wl.Subsurface,
tagsBuffers: [2]Buffer,

clockSurface: *wl.Surface,
clockSubsurface: *wl.Subsurface,
clockBuffers: [2]Buffer,

modulesSurface: *wl.Surface,
modulesSubsurface: *wl.Subsurface,
modulesBuffers: [2]Buffer,

configured: bool,
width: u16,
height: u16,

pub fn create(monitor: *Monitor) !*Surface {
    const state = monitor.state;
    const globals = &state.wayland.globals;

    const self = try state.gpa.create(Surface);
    self.monitor = monitor;
    self.configured = false;

    self.backgroundSurface = try globals.compositor.createSurface();
    self.layerSurface = try globals.layerShell.getLayerSurface(
        self.backgroundSurface,
        monitor.output,
        .top,
        "levee",
    );
    self.backgroundBuffers = mem.zeroes([2]Buffer);

    self.tagsSurface = try globals.compositor.createSurface();
    self.tagsSubsurface = try globals.subcompositor.getSubsurface(
        self.tagsSurface,
        self.backgroundSurface,
    );
    self.tagsBuffers = mem.zeroes([2]Buffer);

    self.clockSurface = try globals.compositor.createSurface();
    self.clockSubsurface = try globals.subcompositor.getSubsurface(
        self.clockSurface,
        self.backgroundSurface,
    );
    self.clockBuffers = mem.zeroes([2]Buffer);

    self.modulesSurface = try globals.compositor.createSurface();
    self.modulesSubsurface = try globals.subcompositor.getSubsurface(
        self.modulesSurface,
        self.backgroundSurface,
    );
    self.modulesBuffers = mem.zeroes([2]Buffer);

    // setup layer surface
    self.layerSurface.setSize(0, state.config.height);
    self.layerSurface.setAnchor(
        .{ .top = true, .left = true, .right = true, .bottom = false },
    );
    self.layerSurface.setExclusiveZone(state.config.height);
    self.layerSurface.setMargin(0, 0, 0, 0);
    self.layerSurface.setListener(*Surface, layerSurfaceListener, self);

    // setup subsurfaces
    self.tagsSubsurface.setPosition(0, 0);
    self.clockSubsurface.setPosition(0, 0);
    self.modulesSubsurface.setPosition(0, 0);

    self.tagsSurface.commit();
    self.clockSurface.commit();
    self.backgroundSurface.commit();

    return self;
}

pub fn destroy(self: *Surface) void {
    self.monitor.surface = null;

    self.backgroundSurface.destroy();
    self.layerSurface.destroy();
    self.backgroundBuffers[0].deinit();
    self.backgroundBuffers[1].deinit();

    self.tagsSurface.destroy();
    self.tagsSubsurface.destroy();
    self.tagsBuffers[0].deinit();
    self.tagsBuffers[1].deinit();

    self.clockSurface.destroy();
    self.clockSubsurface.destroy();
    self.clockBuffers[0].deinit();
    self.clockBuffers[1].deinit();

    self.modulesSurface.destroy();
    self.modulesSubsurface.destroy();
    self.modulesBuffers[0].deinit();
    self.modulesBuffers[1].deinit();

    self.monitor.state.gpa.destroy(self);
}

fn layerSurfaceListener(
    layerSurface: *zwlr.LayerSurfaceV1,
    event: zwlr.LayerSurfaceV1.Event,
    surface: *Surface,
) void {
    switch (event) {
        .configure => |data| {
            surface.configured = true;
            surface.width = @intCast(u16, data.width);
            surface.height = @intCast(u16, data.height);

            layerSurface.ackConfigure(data.serial);

            render.renderBackground(surface) catch return;
            render.renderTags(surface) catch return;
            render.renderClock(surface) catch return;
            render.renderModules(surface) catch return;

            surface.tagsSurface.commit();
            surface.clockSurface.commit();
            surface.modulesSurface.commit();
            surface.backgroundSurface.commit();
        },
        .closed => {
            surface.destroy();
        },
    }
}
