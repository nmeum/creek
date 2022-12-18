const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

const Modules = @This();

const Backlight = @import("modules/Backlight.zig");
const Battery = @import("modules/Battery.zig");
const Pulse = @import("modules/Pulse.zig");

var state = &@import("root").state;

const Tag = enum { backlight, battery, pulse };

backlight: ?Backlight = null,
battery: ?Battery = null,
pulse: ?Pulse = null,
order: ArrayList(Tag),

pub fn init() Modules {
    return Modules{ .order = ArrayList(Tag).init(state.gpa) };
}

pub fn deinit(self: *Modules) void {
    if (self.backlight) |*mod| mod.deinit();
    if (self.battery) |*mod| mod.deinit();
    if (self.pulse) |*mod| mod.deinit();
    self.order.deinit();
}

pub fn register(self: *Modules, name: []const u8) !void {
    if (mem.eql(u8, name, "backlight")) {
        self.backlight = try Backlight.init();
        try self.order.append(.backlight);
    } else if (mem.eql(u8, name, "battery")) {
        self.battery = try Battery.init();
        try self.order.append(.battery);
    } else if (mem.eql(u8, name, "pulse")) {
        self.pulse = try Pulse.init();
        try self.pulse.?.start();
        try self.order.append(.pulse);
    } else {
        return error.UnknownModule;
    }
}
