const std = @import("std");
const heap = std.heap;
const mem = std.mem;

const fcft = @import("fcft");

const Config = @import("config.zig").Config;
const Loop = @import("Loop.zig");
const modules = @import("modules.zig");
const Wayland = @import("wayland.zig").Wayland;

pub const State = struct {
    gpa: mem.Allocator,
    config: Config,
    wayland: Wayland,
    loop: Loop,

    alsa: modules.Alsa,
    backlight: modules.Backlight,
    battery: modules.Battery,
    modules: std.ArrayList(modules.Module),
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
    state.loop = try Loop.init(&state);

    // modules
    state.modules = std.ArrayList(modules.Module).init(state.gpa);
    defer state.modules.deinit();

    state.alsa = try modules.Alsa.init(&state);
    state.backlight = try modules.Backlight.init(&state);
    defer state.backlight.deinit();
    state.battery = try modules.Battery.init(&state);
    defer state.battery.deinit();

    try state.modules.appendSlice(&.{
        try state.backlight.module(),
        state.battery.module(),
        state.alsa.module(),
    });

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}
