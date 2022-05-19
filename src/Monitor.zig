const wl = @import("wayland").client.wl;

const State = @import("main.zig").State;
const Bar = @import("Bar.zig");
const Tags = @import("Tags.zig");
const Monitor = @This();

state: *State,
output: *wl.Output,
globalName: u32,
scale: i32,

bar: ?*Bar,
tags: *Tags,

pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Monitor {
    const self = try state.gpa.create(Monitor);
    self.state = state;
    self.output = try registry.bind(name, wl.Output, 4);
    self.globalName = name;
    self.scale = 1;

    self.bar = null;
    self.tags = try Tags.create(state, self);

    self.output.setListener(*Monitor, listener, self);
    return self;
}

pub fn destroy(self: *Monitor) void {
    if (self.bar) |bar| {
        bar.destroy();
    }
    self.tags.destroy();
    self.state.gpa.destroy(self);
}

fn listener(_: *wl.Output, event: wl.Output.Event, monitor: *Monitor) void {
    switch (event) {
        .scale => |scale| {
            monitor.scale = scale.factor;
        },
        .geometry => {},
        .mode => {},
        .done => {
            if (monitor.bar) |_| {} else {
                monitor.bar = Bar.create(monitor) catch return;
            }
        },
    }
}
