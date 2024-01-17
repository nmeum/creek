const std = @import("std");
const heap = std.heap;
const io = std.io;
const log = std.log;
const mem = std.mem;
const os = std.os;
const process = std.process;

const fcft = @import("fcft");

const Config = @import("Config.zig");
const Loop = @import("Loop.zig");
const Wayland = @import("Wayland.zig");

pub const State = struct {
    gpa: mem.Allocator,
    config: Config,
    wayland: Wayland,
    loop: Loop,
};

pub var state: State = undefined;

pub fn main() anyerror!void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    _ = fcft.init(.auto, false, .warning);

    // initialization
    state.gpa = gpa.allocator();
    state.config = try Config.init();
    state.wayland = try Wayland.init();
    state.loop = try Loop.init();

    defer {
        state.wayland.deinit();
    }

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}
