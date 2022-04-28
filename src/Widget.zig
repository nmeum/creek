const std = @import("std");
const mem = std.mem;

const wl = @import("wayland").client.wl;

const Buffer = @import("Buffer.zig");
const State = @import("main.zig").State;
const Widget = @This();

surface: *wl.Surface,
subsurface: *wl.Subsurface,
buffers: [2]Buffer,

pub fn init(state: *State, background: *wl.Surface) !Widget {
    const globals = &state.wayland.globals;

    const surface = try globals.compositor.createSurface();
    const subsurface = try globals.subcompositor.getSubsurface(
        surface,
        background,
    );

    return Widget{
        .surface = surface,
        .subsurface = subsurface,
        .buffers = mem.zeroes([2]Buffer),
    };
}

pub fn deinit(self: *Widget) void {
    self.surface.destroy();
    self.subsurface.destroy();
    self.buffers[0].deinit();
    self.buffers[1].deinit();
}
