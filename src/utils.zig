const std = @import("std");
const log = std.log;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const unicode = std.unicode;

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    os.exit(1);
}

pub fn cast(comptime to: type) fn (*anyopaque) *to {
    return (struct {
        pub fn cast(module: *anyopaque) *to {
            return @ptrCast(*to, @alignCast(@alignOf(to), module));
        }
    }).cast;
}

pub fn Mask(comptime container: type) type {
    const len = meta.fields(container).len;
    return [len]bool;
}

pub fn toUtf8(gpa: mem.Allocator, bytes: []const u8) ![]u32 {
    const utf8 = try unicode.Utf8View.init(bytes);
    var iter = utf8.iterator();

    var runes = try gpa.alloc(u32, bytes.len);
    var i: usize = 0;
    while (iter.nextCodepoint()) |rune| : (i += 1) {
        runes[i] = rune;
    }

    runes = gpa.resize(runes, i).?;
    return runes;
}
