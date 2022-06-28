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

pub fn main() anyerror!void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    _ = fcft.init(.auto, false, .warning);

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
    var args = process.args();
    const program_name = args.nextPosix() orelse unreachable;

    while (args.nextPosix()) |arg| {
        if (mem.eql(u8, arg, "backlight")) {
            try state.modules.register(Modules.Backlight);
        } else if (mem.eql(u8, arg, "battery")) {
            try state.modules.register(Modules.Battery);
        } else if (mem.eql(u8, arg, "pulse")) {
            try state.modules.register(Modules.Pulse);
        } else {
            try help(program_name);
            return;
        }
    }

    if (state.modules.modules.items.len == 0) {
        try help(program_name);
        return;
    }

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}

fn help(program_name: []const u8) !void {
    const help_text =
        \\Usage: {s} [module]...
        \\
        \\Available modules:
        \\    backlight   screen brightness
        \\    battery     battery capacity
        \\    pulse       speaker volume with pulseaudio
        \\
    ;
    try io.getStdErr().writer().print(help_text, .{program_name});
}
