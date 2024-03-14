const std = @import("std");
const log = std.log;

const wl = @import("wayland").client.wl;

const Bar = @import("Bar.zig");
const Tags = @import("Tags.zig");
const Seat = @import("Seat.zig");
pub const Monitor = @This();

const state = &@import("root").state;

output: *wl.Output,
globalName: u32,
scale: i32,

bar: ?*Bar,
tags: *Tags,

pub fn create(registry: *wl.Registry, name: u32) !*Monitor {
    const self = try state.gpa.create(Monitor);
    self.output = try registry.bind(name, wl.Output, 4);
    self.globalName = name;
    self.scale = 1;

    self.bar = null;
    self.tags = try Tags.create(self);

    self.output.setListener(*Monitor, listener, self);
    return self;
}

pub fn destroy(self: *Monitor) void {
    if (self.bar) |bar| {
        bar.destroy();
    }
    self.tags.destroy();
    state.gpa.destroy(self);
}

pub fn confBar(self: *Monitor) ?*Bar {
    if (self.bar) |bar| {
        if (bar.configured) {
            return bar;
        }
    }

    return null;
}

fn listener(_: *wl.Output, event: wl.Output.Event, monitor: *Monitor) void {
    switch (event) {
        .scale => |scale| {
            monitor.scale = scale.factor;
        },
        .geometry => {},
        .mode => {},
        .done => {
            if (monitor.bar) |_| {
                return;
            }
            monitor.bar = Bar.create(monitor) catch |err| {
                log.err("cannot create bar for monitor {}: {s}",
                        .{monitor.globalName, @errorName(err)});
                return;
            };
        },
    }
}
