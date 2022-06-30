const std = @import("std");
const log = std.log;
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const strcmp = std.cstr.cmp;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;
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
fd: os.fd_t,

monitors: ArrayList(*Monitor),
inputs: ArrayList(*Input),
globals: Globals,
globalsMask: GlobalsMask,

const Globals = struct {
    compositor: *wl.Compositor,
    subcompositor: *wl.Subcompositor,
    shm: *wl.Shm,
    viewporter: *wp.Viewporter,
    layerShell: *zwlr.LayerShellV1,
    statusManager: *zriver.StatusManagerV1,
    control: *zriver.ControlV1,
};
const GlobalsMask = utils.Mask(Globals);

pub fn init(state: *State) !Wayland {
    const display = try wl.Display.connect(null);
    const wfd = wfd: {
        const fd = display.getFd();
        break :wfd @intCast(os.fd_t, fd);
    };

    return Wayland{
        .state = state,
        .display = display,
        .fd = wfd,
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

    inline for (@typeInfo(Globals).Struct.fields) |field, i| {
        if (self.globalsMask[i]) {
            @field(self.globals, field.name).destroy();
        }
    }
    self.display.disconnect();
}

pub fn registerGlobals(self: *Wayland) !void {
    const registry = try self.display.getRegistry();
    defer registry.destroy();

    registry.setListener(*State, registryListener, self.state);
    const errno = self.display.roundtrip();
    if (errno != .SUCCESS) return error.RoundtripFailed;
    for (self.globalsMask) |is_registered| if (!is_registered) {
        return error.GlobalNotAdvertized;
    };
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

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, state: *State) void {
    const self = &state.wayland;
    switch (event) {
        .global => |g| {
            self.bindGlobal(registry, g.name, g.interface, g.version) catch |err| switch (err) {
                error.OutOfMemory => {
                    log.err("out of memory", .{});
                    return;
                },
            };
        },
        .global_remove => |g| {
            for (self.monitors.items) |monitor, i| if (monitor.globalName == g.name) {
                monitor.destroy();
                _ = self.monitors.swapRemove(i);
                break;
            };
            for (self.inputs.items) |input, i| if (input.globalName == g.name) {
                input.destroy();
                _ = self.inputs.swapRemove(i);
                break;
            };
        },
    }
}

fn bindGlobal(self: *Wayland, registry: *wl.Registry, name: u32, iface: [*:0]const u8, version: u32) !void {
    if (strcmp(iface, wl.Compositor.getInterface().name) == 0) {
        if (version < 4) {
            log.err("wl_compositor version 4 is required", .{});
            return;
        }
        const global = try registry.bind(name, wl.Compositor, 4);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Subcompositor.getInterface().name) == 0) {
        const global = try registry.bind(name, wl.Subcompositor, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Shm.getInterface().name) == 0) {
        const global = try registry.bind(name, wl.Shm, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, wp.Viewporter.getInterface().name) == 0) {
        const global = try registry.bind(name, wp.Viewporter, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, zwlr.LayerShellV1.getInterface().name) == 0) {
        const global = try registry.bind(name, zwlr.LayerShellV1, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, zriver.StatusManagerV1.getInterface().name) == 0) {
        const global = try registry.bind(name, zriver.StatusManagerV1, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, zriver.ControlV1.getInterface().name) == 0) {
        const global = try registry.bind(name, zriver.ControlV1, 1);
        self.setGlobal(global);
    } else if (strcmp(iface, wl.Output.getInterface().name) == 0) {
        if (version < 3) {
            log.err("wl_output version 3 is required", .{});
            return;
        }
        const monitor = try Monitor.create(self.state, registry, name);
        try self.monitors.append(monitor);
    } else if (strcmp(iface, wl.Seat.getInterface().name) == 0) {
        if (version < 5) {
            log.err("wl_seat version 5 is required", .{});
            return;
        }
        const input = try Input.create(self.state, registry, name);
        try self.inputs.append(input);
    }
}

fn setGlobal(self: *Wayland, global: anytype) void {
    inline for (meta.fields(Globals)) |field, i| {
        if (field.field_type == @TypeOf(global)) {
            @field(self.globals, field.name) = global;
            self.globalsMask[i] = true;
            break;
        }
    }
}
