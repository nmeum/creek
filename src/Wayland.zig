const std = @import("std");
const log = std.log;
const mem = std.mem;
const meta = std.meta;
const posix = std.posix;

const wl = @import("wayland").client.wl;
const wp = @import("wayland").client.wp;
const zwlr = @import("wayland").client.zwlr;
const zriver = @import("wayland").client.zriver;

const Bar = @import("Bar.zig");
const Input = @import("Input.zig");
const Monitor = @import("Monitor.zig");
const Seat = @import("Seat.zig");
const Wayland = @This();

const state = &@import("root").state;

display: *wl.Display,
registry: *wl.Registry,
fd: posix.fd_t,

compositor: ?*wl.Compositor = null,
subcompositor: ?*wl.Subcompositor = null,
seat: ?*wl.Seat = null,
shm: ?*wl.Shm = null,
single_pixel_buffer_manager: ?*wp.SinglePixelBufferManagerV1 = null,
viewporter: ?*wp.Viewporter = null,
layer_shell: ?*zwlr.LayerShellV1 = null,
status_manager: ?*zriver.StatusManagerV1 = null,
control: ?*zriver.ControlV1 = null,

river_seat: ?*Seat = null,
monitors: std.ArrayList(*Monitor),
inputs: std.ArrayList(*Input),

pub fn init() !Wayland {
    const display = try wl.Display.connect(null);
    const wfd: posix.fd_t = @intCast(display.getFd());
    const registry = try display.getRegistry();

    return Wayland{
        .display = display,
        .registry = registry,
        .fd = wfd,
        .monitors = std.ArrayList(*Monitor).init(state.gpa),
        .inputs = std.ArrayList(*Input).init(state.gpa),
    };
}

pub fn deinit(self: *Wayland) void {
    for (self.monitors.items) |monitor| monitor.destroy();
    for (self.inputs.items) |input| input.destroy();

    if (self.river_seat) |s| s.destroy();
    self.monitors.deinit();
    self.inputs.deinit();

    if (self.compositor) |global| global.destroy();
    if (self.subcompositor) |global| global.destroy();
    if (self.shm) |global| global.destroy();
    if (self.viewporter) |global| global.destroy();
    if (self.single_pixel_buffer_manager) |global| global.destroy();
    if (self.layer_shell) |global| global.destroy();
    if (self.status_manager) |global| global.destroy();
    if (self.control) |global| global.destroy();
    // TODO: Do we need to .release() the seat?
    if (self.seat) |global| global.destroy();

    self.registry.destroy();
    self.display.disconnect();
}

pub fn registerGlobals(self: *Wayland) !void {
    self.registry.setListener(*Wayland, registryListener, self);

    const errno = self.display.roundtrip();
    if (errno != .SUCCESS) {
        return error.RoundtripFailed;
    }
}

pub fn findBar(self: *Wayland, wlSurface: ?*wl.Surface) ?*Bar {
    if (wlSurface == null) {
        return null;
    }
    for (self.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.background.surface == wlSurface or
                bar.title.surface == wlSurface or
                bar.tags.surface == wlSurface or
                bar.text.surface == wlSurface)
            {
                return bar;
            }
        }
    }
    return null;
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, self: *Wayland) void {
    switch (event) {
        .global => |g| {
            self.bindGlobal(registry, g.name, g.interface) catch unreachable;
        },
        .global_remove => |g| {
            for (self.monitors.items, 0..) |monitor, i| {
                if (monitor.globalName == g.name) {
                    self.monitors.swapRemove(i).destroy();
                    break;
                }
            }
            for (self.inputs.items, 0..) |input, i| {
                if (input.globalName == g.name) {
                    self.inputs.swapRemove(i).destroy();
                    break;
                }
            }
        },
    }
}

fn bindGlobal(self: *Wayland, registry: *wl.Registry, name: u32, iface: [*:0]const u8) !void {
    if (mem.orderZ(u8, iface, wl.Compositor.interface.name) == .eq) {
        self.compositor = try registry.bind(name, wl.Compositor, 4);
    } else if (mem.orderZ(u8, iface, wl.Subcompositor.interface.name) == .eq) {
        self.subcompositor = try registry.bind(name, wl.Subcompositor, 1);
    } else if (mem.orderZ(u8, iface, wl.Shm.interface.name) == .eq) {
        self.shm = try registry.bind(name, wl.Shm, 1);
    } else if (mem.orderZ(u8, iface, wp.Viewporter.interface.name) == .eq) {
        self.viewporter = try registry.bind(name, wp.Viewporter, 1);
    } else if (mem.orderZ(u8, iface, wp.SinglePixelBufferManagerV1.interface.name) == .eq) {
        self.single_pixel_buffer_manager = try registry.bind(name, wp.SinglePixelBufferManagerV1, 1);
    } else if (mem.orderZ(u8, iface, zwlr.LayerShellV1.interface.name) == .eq) {
        self.layer_shell = try registry.bind(name, zwlr.LayerShellV1, 1);
    } else if (mem.orderZ(u8, iface, zriver.StatusManagerV1.interface.name) == .eq) {
        self.status_manager = try registry.bind(name, zriver.StatusManagerV1, 2);
        self.river_seat = try Seat.create(); // TODO: find a better way to do this
    } else if (mem.orderZ(u8, iface, zriver.ControlV1.interface.name) == .eq) {
        self.control = try registry.bind(name, zriver.ControlV1, 1);
    } else if (mem.orderZ(u8, iface, wl.Output.interface.name) == .eq) {
        const monitor = try Monitor.create(registry, name);
        try self.monitors.append(monitor);
    } else if (mem.orderZ(u8, iface, wl.Seat.interface.name) == .eq) {
        self.seat = try registry.bind(name, wl.Seat, 5);
        try self.inputs.append(try Input.create(name));
    }
}
