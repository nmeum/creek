const std = @import("std");
const heap = std.heap;
const mem = std.mem;

const fcft = @import("fcft");

const Config = @import("Config.zig");
const Loop = @import("Loop.zig");
const Modules = @import("Modules.zig");
const Wayland = @import("wayland.zig").Wayland;

pub const State = struct {
    gpa: mem.Allocator,
    config: Config,
    wayland: Wayland,
    modules: Modules,
    loop: Loop,
};

pub fn main() anyerror!void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    fcft.init(.auto, false, .info);

    // initialization
    var state: State = undefined;
    state.gpa = gpa.allocator();
    state.config = try Config.init();
    state.wayland = try Wayland.init(&state);
    defer state.wayland.deinit();
    state.modules = Modules.init(&state);
    defer state.modules.deinit();
    state.loop = try Loop.init(&state);

    // modules
    try state.modules.register(Modules.Alsa);
    try state.modules.register(Modules.Backlight);
    try state.modules.register(Modules.Battery);

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}
