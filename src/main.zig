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
const Modules = @import("Modules.zig");
const Wayland = @import("Wayland.zig");

pub const State = struct {
    gpa: mem.Allocator,
    config: Config,
    wayland: Wayland,
    modules: Modules,
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
    state.modules = Modules.init();
    state.loop = try Loop.init();

    defer {
        state.wayland.deinit();
        state.modules.deinit();
    }

    // modules
    var args = process.args();
    const program_name = args.next() orelse unreachable;

    while (args.next()) |arg| {
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            help(program_name);
            return;
        }
        state.modules.register(arg) catch |err| {
            switch (err) {
                error.UnknownModule => {
                    log.err("unknown module: {s}", .{arg});
                },
                else => {
                    log.err(
                        "initialization error for module {s}: {s}",
                        .{ arg, @errorName(err) },
                    );
                },
            }
            return;
        };
    }

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}

fn help(program_name: []const u8) void {
    const text =
        \\Usage: {s} [module]...
        \\
        \\Available modules:
        \\    backlight   screen brightness
        \\    battery     battery capacity
        \\    pulse       speaker volume with pulseaudio
        \\
    ;
    const w = io.getStdErr().writer();
    w.print(text, .{program_name}) catch unreachable;
}
