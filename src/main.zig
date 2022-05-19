const std = @import("std");
const heap = std.heap;
const io = std.io;
const log = std.log;
const mem = std.mem;
const os = std.os;

const clap = @import("clap");
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

    fcft.init(.auto, false, .warning);

    // cli arguments
    const params = comptime [_]clap.Param(clap.Help){
        try clap.parseParam("-h, --help             Display this help and exit."),
        try clap.parseParam("-m, --module <str>...  Add module."),
    };
    var args = try clap.parse(clap.Help, &params, .{});
    defer args.deinit();
    if (args.flag("--help")) {
        return clap.help(io.getStdErr().writer(), &params);
    }

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
    for (args.options("--module")) |module_name| {
        if (mem.eql(u8, module_name, "backlight")) {
            try state.modules.register(Modules.Backlight);
        } else if (mem.eql(u8, module_name, "battery")) {
            try state.modules.register(Modules.Battery);
        } else if (mem.eql(u8, module_name, "pulse")) {
            try state.modules.register(Modules.Pulse);
        } else {
            log.err("unknown module: {s}", .{module_name});
            return clap.help(io.getStdErr().writer(), &params);
        }
    }

    if (state.modules.modules.items.len == 0) {
        log.err("having no modules is currently not supported", .{});
        return clap.help(io.getStdErr().writer(), &params);
    }

    // event loop
    try state.wayland.registerGlobals();
    try state.loop.run();
}
