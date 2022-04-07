const std = @import("std");
const meta = std.meta;

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
