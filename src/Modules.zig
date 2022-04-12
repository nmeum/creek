const std = @import("std");
const ArrayList = std.ArrayList;

const Event = @import("Loop.zig").Event;
const State = @import("main.zig").State;
const Modules = @This();

state: *State,
modules: ArrayList(Module),

pub const Alsa = @import("modules/Alsa.zig");
pub const Backlight = @import("modules/Backlight.zig");
pub const Battery = @import("modules/Battery.zig");

pub const Module = struct {
    impl: *anyopaque,
    funcs: struct {
        getEvent: fn (*anyopaque) anyerror!Event,
        print: fn (*anyopaque, StringWriter) anyerror!void,
        destroy: fn (*anyopaque) void,
    },

    pub const StringWriter = std.ArrayList(u8).Writer;

    pub fn getEvent(self: *Module) !Event {
        return self.funcs.getEvent(self.impl);
    }

    pub fn print(self: *Module, writer: StringWriter) !void {
        return self.funcs.print(self.impl, writer);
    }

    pub fn destroyInstance(self: *Module) void {
        return self.funcs.destroy(self.impl);
    }
};

pub fn init(state: *State) Modules {
    return Modules{
        .state = state,
        .modules = ArrayList(Module).init(state.gpa),
    };
}

pub fn deinit(self: *Modules) void {
    for (self.modules.items) |*module| module.destroyInstance();
    self.modules.deinit();
}

pub fn register(self: *Modules, comptime ModuleType: type) !void {
    const instance = try ModuleType.create(self.state);
    try self.modules.append(try instance.module());
}
