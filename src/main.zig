const std = @import("std");

const fcft = @import("fcft");

const Config = @import("config.zig").Config;
const Loop = @import("event.zig").Loop;
const modules = @import("modules.zig");
const Wayland = @import("wayland.zig").Wayland;

pub const State = struct {
    allocator: std.mem.Allocator,
    config: Config,
    wayland: Wayland,
    loop: Loop,

    battery: modules.Battery,
    backlight: modules.Backlight,
    modules: std.ArrayList(modules.Module),
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    fcft.init(.auto, false, .info);

    std.log.info("initialization", .{});
    var state: State = undefined;
    state.allocator = arena.allocator();
    state.config = try Config.init();
    state.wayland = try Wayland.init(&state);
    state.loop = try Loop.init(&state);

    std.log.info("modules initialization", .{});
    state.modules = std.ArrayList(modules.Module).init(state.allocator);
    state.backlight = try modules.Backlight.init(&state);
    try state.modules.append(state.backlight.module());
    state.battery = try modules.Battery.init(&state);
    try state.modules.append(state.battery.module());

    std.log.info("wayland globals registration", .{});
    try state.wayland.registerGlobals();

    std.log.info("event loop start", .{});
    try state.loop.run();
}
