const std = @import("std");

const Event = @import("Loop.zig").Event;

pub const Alsa = @import("modules/Alsa.zig");
pub const Backlight = @import("modules/Backlight.zig");
pub const Battery = @import("modules/Battery.zig");

pub const Module = struct {
    impl: *anyopaque,
    eventFn: fn (*anyopaque) anyerror!Event,
    printFn: fn (*anyopaque, StringWriter) anyerror!void,

    pub const StringWriter = std.ArrayList(u8).Writer;

    pub fn getEvent(self: *Module) !Event {
        return self.eventFn(self.impl);
    }

    pub fn print(self: *Module, writer: StringWriter) !void {
        return self.printFn(self.impl, writer);
    }
};
