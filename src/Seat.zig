const std = @import("std");
const log = std.log;
const Mutex = std.Io.Mutex;

const wl = @import("wayland").client.wl;

const Bar = @import("Bar.zig");
const Monitor = @import("Monitor.zig");
const state = &@import("root").state;

pub const Seat = @This();

current_output: ?*wl.Output,
mtx: Mutex,

pub fn create() !*Seat {
    const self = try state.gpa.create(Seat);
    self.mtx = .init;
    self.current_output = null;
    return self;
}

pub fn destroy(self: *Seat) void {
    state.gpa.destroy(self);
}

pub fn focusedMonitor(self: *Seat) ?*Monitor {
    if (self.current_output == null) {
        const items = state.wayland.monitors.items;
        if (items.len > 0) {
            return items[0];
        }
    }

    for (state.wayland.monitors.items) |monitor| {
        if (monitor.output == self.current_output) {
            return monitor;
        }
    }

    return null;
}

pub fn focusedBar(self: *Seat) ?*Bar {
    if (self.focusedMonitor()) |m| {
        return m.confBar();
    }

    return null;
}
