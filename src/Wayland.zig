const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const strcmp = std.cstr.cmp;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const zriver = @import("wayland").client.zriver;

const Bar = @import("Bar.zig");
const Event = @import("Loop.zig").Event;
const Input = @import("Input.zig");
const Monitor = @import("Monitor.zig");
const State = @import("main.zig").State;
const utils = @import("utils.zig");
const Wayland = @This();

state: *State,
display: *wl.Display,
registry: *wl.Registry,

monitors: ArrayList(*Monitor),
inputs: ArrayList(*Input),
globals: Globals,
globalsMask: GlobalsMask,

const Globals = struct {
    compositor: *wl.Compositor,
    subcompositor: *wl.Subcompositor,
    shm: *wl.Shm,
    layerShell: *zwlr.LayerShellV1,
    statusManager: *zriver.StatusManagerV1,
    control: *zriver.ControlV1,
};
const GlobalsMask = utils.Mask(Globals);

pub fn init(state: *State) !Wayland {
    const display = try wl.Display.connect(null);

    return Wayland{
        .state = state,
        .display = display,
        .registry = try display.getRegistry(),
        .monitors = ArrayList(*Monitor).init(state.gpa),
        .inputs = ArrayList(*Input).init(state.gpa),
        .globals = undefined,
        .globalsMask = mem.zeroes(GlobalsMask),
    };
}

pub fn deinit(self: *Wayland) void {
    for (self.monitors.items) |monitor| monitor.destroy();
    for (self.inputs.items) |input| input.destroy();

    self.monitors.deinit();
    self.inputs.deinit();
}

pub fn registerGlobals(self: *Wayland) !void {
    self.registry.setListener(*State, registryListener, self.state);
    _ = try self.display.roundtrip();

    for (self.globalsMask) |is_registered| {
        if (!is_registered) return error.UnsupportedGlobal;
    }
}

pub fn getEvent(self: *Wayland) !Event {
    const fd = self.display.getFd();

    return Event{
        .fd = .{
            .fd = @intCast(os.fd_t, fd),
            .events = os.POLL.IN,
            .revents = undefined,
        },
        .data = @ptrCast(*anyopaque, self),
        .callbackIn = dispatch,
        .callbackOut = flush,
    };
}

fn dispatch(self_opaque: *anyopaque) error{Terminate}!void {
    const self = utils.cast(Wayland)(self_opaque);
    _ = self.display.dispatch() catch return;
}

fn flush(self_opaque: *anyopaque) error{Terminate}!void {
    const self = utils.cast(Wayland)(self_opaque);
    _ = self.display.flush() catch return;
}

fn registryListener(
    registry: *wl.Registry,
    event: wl.Registry.Event,
    state: *State,
) void {
    const self = &state.wayland;

    switch (event) {
        .global => |g| {
            self.bindGlobal(registry, g.interface, g.name) catch return;
        },
        .global_remove => |data| {
            for (self.monitors.items) |monitor, i| {
                if (monitor.globalName == data.name) {
                    monitor.destroy();
                    _ = self.monitors.swapRemove(i);
                    break;
                }
            }
            for (self.inputs.items) |input, i| {
                if (input.globalName == data.name) {
                    input.destroy();
                    _ = self.inputs.swapRemove(i);
                    break;
                }
            }
        },
    }
}

fn bindGlobal(
    self: *Wayland,
    registry: *wl.Registry,
    iface: [*:0]const u8,
    name: u32,
) !void {
    if (strcmp(iface, wl.Compositor.getInterface().name) == 0) {
        const global = try registry.bind(name, wl.Compositor, 4);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Subcompositor.getInterface().name) == 0) {
        const global = try registry.bind(name, wl.Subcompositor, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Shm.getInterface().name) == 0) {
        const global = try registry.bind(name, wl.Shm, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, zwlr.LayerShellV1.getInterface().name) == 0) {
        const global = try registry.bind(name, zwlr.LayerShellV1, 1);
        self.setGlobal(global);
    } else if (
        strcmp(iface, zriver.StatusManagerV1.getInterface().name) == 0
    ) {
        const global = try registry.bind(name, zriver.StatusManagerV1, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, zriver.ControlV1.getInterface().name) == 0) {
        const global = try registry.bind(name, zriver.ControlV1, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Output.getInterface().name) == 0) {
        const monitor = try Monitor.create(self.state, registry, name);
        try self.monitors.append(monitor);
    } else if (strcmp(iface, wl.Seat.getInterface().name) == 0) {
        const input = try Input.create(self.state, registry, name);
        try self.inputs.append(input);
    }
}

pub fn setGlobal(self: *Wayland, global: anytype) void {
    inline for (meta.fields(Globals)) |field, i| {
        if (field.field_type == @TypeOf(global)) {
            @field(self.globals, field.name) = global;
            self.globalsMask[i] = true;
            break;
        }
    }
}

pub fn findBar(self: *Wayland, wlSurface: ?*wl.Surface) ?*Bar {
    if (wlSurface == null) {
        return null;
    }
    for (self.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.background.surface == wlSurface or
                bar.tags.surface == wlSurface or
                bar.clock.surface == wlSurface or
                bar.modules.surface == wlSurface)
            {
                return bar;
            }
        }
    }
    return null;
}
