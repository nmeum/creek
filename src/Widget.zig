const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").client.wl;

const Buffer = @import("Buffer.zig");
const Widget = @This();

const state = &@import("root").state;

surface: *wl.Surface,
subsurface: *wl.Subsurface,
buffers: [2]Buffer,

pub fn init(background: *wl.Surface) !Widget {
    const compositor = state.wayland.compositor.?;
    const subcompositor = state.wayland.subcompositor.?;

    const surface = try compositor.createSurface();
    const subsurface = try subcompositor.getSubsurface(surface, background);

    return Widget{
        .surface = surface,
        .subsurface = subsurface,
        .buffers = .{ .{}, .{} },
    };
}

pub fn deinit(self: *Widget) void {
    self.surface.destroy();
    self.subsurface.destroy();
    self.buffers[0].deinit();
    self.buffers[1].deinit();
}
