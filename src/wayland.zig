const std = @import("std");
const mem = std.mem;
const meta = std.meta;
const os = std.os;
const strcmp = std.cstr.cmp;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const zriver = @import("wayland").client.zriver;

const Buffer = @import("Buffer.zig");
const Event = @import("Loop.zig").Event;
const render = @import("render.zig");
const State = @import("main.zig").State;
const Bar = @import("Bar.zig");
const Tags = @import("Tags.zig");
const utils = @import("utils.zig");

pub const Wayland = struct {
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
};

pub const Monitor = struct {
    state: *State,
    output: *wl.Output,
    globalName: u32,
    scale: i32,

    bar: ?*Bar,
    tags: *Tags,

    pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Monitor {
        const self = try state.gpa.create(Monitor);
        self.state = state;
        self.output = try registry.bind(name, wl.Output, 3);
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
            .name => {},
            .description => {},
            .done => {
                if (monitor.bar) |_| {} else {
                    monitor.bar = Bar.create(monitor) catch return;
                }
            },
        }
    }
};

pub const Input = struct {
    state: *State,
    seat: *wl.Seat,
    globalName: u32,

    pointer: struct {
        wlPointer: ?*wl.Pointer,
        x: i32,
        y: i32,
        bar: ?*Bar,
    },

    pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Input {
        const self = try state.gpa.create(Input);
        self.state = state;
        self.seat = try registry.bind(name, wl.Seat, 3);
        self.globalName = name;

        self.pointer.wlPointer = null;
        self.pointer.bar = null;

        self.seat.setListener(*Input, listener, self);
        return self;
    }

    pub fn destroy(self: *Input) void {
        if (self.pointer.wlPointer) |wlPointer| {
            wlPointer.release();
        }
        self.seat.release();
        self.state.gpa.destroy(self);
    }

    fn listener(seat: *wl.Seat, event: wl.Seat.Event, input: *Input) void {
        switch (event) {
            .capabilities => |data| {
                if (input.pointer.wlPointer) |wlPointer| {
                    wlPointer.release();
                    input.pointer.wlPointer = null;
                }
                if (data.capabilities.pointer) {
                    input.pointer.wlPointer = seat.getPointer() catch return;
                    input.pointer.wlPointer.?.setListener(
                        *Input,
                        pointerListener,
                        input,
                    );
                }
            },
            .name => {},
        }
    }

    fn pointerListener(
        _: *wl.Pointer,
        event: wl.Pointer.Event,
        input: *Input,
    ) void {
        switch (event) {
            .enter => |data| {
                input.pointer.x = data.surface_x.toInt();
                input.pointer.y = data.surface_y.toInt();
                const bar = input.state.wayland.findBar(data.surface);
                input.pointer.bar = bar;
            },
            .leave => |_| {
                input.pointer.bar = null;
            },
            .motion => |data| {
                input.pointer.x = data.surface_x.toInt();
                input.pointer.y = data.surface_y.toInt();
            },
            .button => |data| {
                if (data.state != .pressed) return;
                if (input.pointer.bar) |bar| {
                    if (!bar.configured) return;

                    const x = @intCast(u32, input.pointer.x);
                    if (x < bar.height * 9) {
                        bar.monitor.tags.handleClick(x, input) catch return;
                    }
                }
            },
            else => {},
        }
    }
};
