const std = @import("std");
const os = std.os;
const fmt = std.fmt;
const testing = std.testing;

const fcft = @import("fcft");
const pixman = @import("pixman");

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
backgroundColor: pixman.Color,
foregroundColor: pixman.Color,
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
        .red = r,
        .green = g,
        .blue = b,
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

fn stringEnv(def: [:0]const u8, key: []const u8) [:0]const u8 {
    var val = os.getenv(key);
    if (val) |v| {
        return v[0..v.len :0]; // Not needed with Zig 0.11
    } else {
        return def;
    }
}

pub fn init() !Config {
    var font_name = stringEnv("monospace:size=14", "LEVEE_FONT");
    var font_names = [_][*:0]const u8{font_name};

    const height = try numberEnv(32, "LEVEE_HEIGHT");
    const border = try numberEnv(2, "LEVEE_BORDER");

    return Config{
        .height = @intCast(u16, height),
        .backgroundColor = try colorEnv(BlackColor, "LEVEE_BGCOLOR"),
        .foregroundColor = try colorEnv(WhiteColor, "LEVEE_FGCOLOR"),
        .border = @intCast(u15, border),
        .font = try fcft.Font.fromName(&font_names, null),
    };
}

test "color parsing" {
    const color = try parseColor("0xdeadbe");
    try testing.expect(color.red == 0xde);
    try testing.expect(color.green == 0xad);
    try testing.expect(color.blue == 0xbe);

    try testing.expectError(
        fmt.ParseIntError.Overflow,
        parseColor("0xffffffff")
    );
}
