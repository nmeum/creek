const std = @import("std");

const Config = @import("config.zig").Config;
const Loop = @import("event.zig").Loop;
const Wayland = @import("wayland.zig").Wayland;

pub const State = struct {
    allocator: std.mem.Allocator,
    config: Config,
    wayland: Wayland,
    loop: Loop,
};

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    std.log.info("initialization", .{});
    var state: State = undefined;
    state.allocator = arena.allocator();
    state.config = Config.init();
    state.wayland = try Wayland.init(&state);
    state.loop = try Loop.init(&state);

    std.log.info("wayland globals registration", .{});
    try state.wayland.registerGlobals();

    std.log.info("event loop start", .{});
    try state.loop.run();
}
