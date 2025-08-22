const std = @import("std");
const heap = std.heap;
const io = std.io;
const log = std.log;
const mem = std.mem;
const posix = std.posix;
const os = std.os;
const fmt = std.fmt;
const process = std.process;

const fcft = @import("fcft");
const pixman = @import("pixman");

const flags = @import("flags.zig");
const Loop = @import("Loop.zig");
const Wayland = @import("Wayland.zig");

pub const Config = struct {
    height: u16,
    normalFgColor: pixman.Color,
    normalBgColor: pixman.Color,
    focusFgColor: pixman.Color,
    focusBgColor: pixman.Color,
    font: *fcft.Font,
};

pub const State = struct {
    gpa: mem.Allocator,
    config: Config,
    wayland: Wayland,
    loop: Loop,
};

pub var state: State = undefined;

fn parseColor(str: []const u8) !pixman.Color {
    // Color string needs to contain a base prefix.
    // For example: 0xRRGGBB.
    const val = try fmt.parseInt(u24, str, 0);

    const r: u8 = @truncate(val >> 16);
    const g: u8 = @truncate(val >> 8);
    const b: u8 = @truncate(val);

    return pixman.Color{
        .red = @as(u16, r) << 8 | 0xff,
        .green = @as(u16, g) << 8 | 0xff,
        .blue = @as(u16, b) << 8 | 0xff,
        .alpha = 0xffff,
    };
}

fn parseColorFlag(flg: ?[]const u8, def: []const u8) !pixman.Color {
    if (flg) |raw| {
        return parseColor(raw);
    } else {
        return parseColor(def);
    }
}

fn parseFlags(args: [][*:0]u8) !Config {
    const result = flags.parser([*:0]const u8, &.{
        .{ .name = "hg", .kind = .arg }, // height
        .{ .name = "fn", .kind = .arg }, // font name
        .{ .name = "nf", .kind = .arg }, // normal foreground
        .{ .name = "nb", .kind = .arg }, // normal background
        .{ .name = "ff", .kind = .arg }, // focused foreground
        .{ .name = "fb", .kind = .arg }, // focused background
    }).parse(args) catch {
        usage();
    };

    var font_names = if (result.flags.@"fn") |raw| blk: {
        break :blk [_][*:0]const u8{raw};
    } else blk: {
        break :blk [_][*:0]const u8{"monospace:size=10"};
    };

    const font = try fcft.Font.fromName(&font_names, null);
    const height: u16 = if (result.flags.hg) |raw| blk: {
        break :blk try fmt.parseUnsigned(u16, raw, 10);
    } else blk: {
        break :blk @intFromFloat(@as(f32, @floatFromInt(font.height)) * 1.5);
    };

    return Config{
        .font = font,
        .height = @intCast(height),
        .normalFgColor = try parseColorFlag(result.flags.nf, "0xb8b8b8"),
        .normalBgColor = try parseColorFlag(result.flags.nb, "0x282828"),
        .focusFgColor = try parseColorFlag(result.flags.ff, "0x181818"),
        .focusBgColor = try parseColorFlag(result.flags.fb, "0x7cafc2"),
    };
}

pub fn usage() noreturn {
    const desc =
        \\usage: creek [-hg HEIGHT] [-fn FONT] [-nf COLOR] [-nb COLOR]
        \\             [-ff COLOR] [-fb COLOR]
        \\
    ;

    var buffer: [1024]u8 = undefined;
    var serr = std.fs.File.stderr().writer(&buffer);
    serr.interface.writeAll(desc) catch |err| {
        std.debug.panic("{s}", .{@errorName(err)});
    };
    serr.end() catch |err| {
        std.debug.panic("{s}", .{@errorName(err)});
    };

    process.exit(1);
}

pub fn main() anyerror!void {
    var gpa: heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();

    _ = fcft.init(.auto, false, .warning);
    if (fcft.capabilities() & fcft.Capabilities.text_run_shaping == 0) {
        @panic("Support for text run shaping required in fcft and not present");
    }

    state.gpa = gpa.allocator();
    state.wayland = try Wayland.init();
    state.loop = try Loop.init();
    state.config = parseFlags(os.argv[1..]) catch |err| {
        log.err("Option parsing failed with: {s}", .{@errorName(err)});
        usage();
    };

    defer {
        state.wayland.deinit();
    }

    try state.wayland.registerGlobals();
    try state.loop.run();
}
