const std = @import("std");
const os = std.os;
const fmt = std.fmt;
const testing = std.testing;

const fcft = @import("fcft");
const pixman = @import("pixman");

const state = &@import("root").state;

const BlackColor = pixman.Color{
    .red = 0,
    .green = 0,
    .blue = 0,
    .alpha = 0xffff,
};

const WhiteColor = pixman.Color{
    .red = 0xffff,
    .green = 0xffff,
    .blue = 0xffff,
    .alpha = 0xffff,
};

const Config = @This();

height: u16,
normalBgColor: pixman.Color,
normalFgColor: pixman.Color,
focusBgColor: pixman.Color,
focusFgColor: pixman.Color,
border: u15,
font: *fcft.Font,

fn parseColor(str: []const u8) !pixman.Color {
    // Color string needs to contain a base prefix.
    // For example: 0xRRGGBB.
    const val = try fmt.parseInt(u24, str, 0);

    const r = @truncate(u8, val >> 16);
    const g = @truncate(u8, val >> 8);
    const b = @truncate(u8, val);

    return pixman.Color{
        .red = @as(u16, r) << 8 | 0xff,
        .green = @as(u16, g) << 8 | 0xff,
        .blue = @as(u16, b) << 8 | 0xff,
        .alpha = 0xffff,
    };
}

fn colorEnv(def: pixman.Color, key: []const u8) !pixman.Color {
    var val = os.getenv(key);
    if (val) |v| {
        return parseColor(v);
    } else {
        return def;
    }
}

fn numberEnv(def: u32, key: []const u8) !u32 {
    var val = os.getenv(key);
    if (val) |v| {
        return fmt.parseInt(u32, v, 10);
    } else {
        return def;
    }
}

// TODO: Memory allocation not needed here with Zig >= 0.11.
fn stringEnv(def: []const u8, key: []const u8) ![:0]const u8 {
    var val = os.getenv(key);
    if (val) |v| {
        const vz = try state.gpa.allocSentinel(u8, v.len, 0);
        std.mem.copy(u8, vz, v);
        return vz;
    } else {
        const vz = try state.gpa.allocSentinel(u8, def.len, 0);
        std.mem.copy(u8, vz, def);
        return vz;
    }
}

pub fn init() !Config {
    var font_name = try stringEnv("monospace:size=14", "LEVEE_FONT");
    defer state.gpa.free(font_name);
    var font_names = [_][*:0]const u8{font_name};

    const height = try numberEnv(32, "LEVEE_HEIGHT");
    const border = try numberEnv(2, "LEVEE_BORDER");

    const bg_color = try colorEnv(BlackColor, "LEVEE_NORMAL_BG");
    const fg_color = try colorEnv(WhiteColor, "LEVEE_NORMAL_FG");

    return Config{
        .height = @intCast(u16, height),
        .normalBgColor = bg_color,
        .normalFgColor = fg_color,
        .focusBgColor = try colorEnv(fg_color, "LEVEE_FOCUS_BG"),
        .focusFgColor = try colorEnv(bg_color, "LEVEE_FOCUS_FG"),
        .border = @intCast(u15, border),
        .font = try fcft.Font.fromName(&font_names, null),
    };
}

test "color parsing" {
    const color = try parseColor("0xdeadbe");
    try testing.expect(color.red == 0xdeff);
    try testing.expect(color.green == 0xadff);
    try testing.expect(color.blue == 0xbeff);

    try testing.expectError(
        fmt.ParseIntError.Overflow,
        parseColor("0xffffffff")
    );
}
