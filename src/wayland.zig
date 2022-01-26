const std = @import("std");
const mem = std.mem;
const strcmp = std.cstr.cmp;
const ArrayList = std.ArrayList;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const zriver = @import("wayland").client.zriver;

const Buffer = @import("shm.zig").Buffer;
const render = @import("render.zig");
const State = @import("main.zig").State;
const Tags = @import("tags.zig").Tags;

pub const Wayland = struct {
    state: *State,
    display: *wl.Display,
    registry: *wl.Registry,

    outputs: ArrayList(*Output),
    seats: ArrayList(*Seat),

    compositor: *wl.Compositor,
    subcompositor: *wl.Subcompositor,
    shm: *wl.Shm,
    layerShell: *zwlr.LayerShellV1,
    statusManager: *zriver.StatusManagerV1,
    control: *zriver.ControlV1,

    globalsRegistered: [6]bool,

    pub fn init(state: *State) !Wayland {
        const display = try wl.Display.connect(null);

        return Wayland{
            .state = state,
            .display = display,
            .registry = try display.getRegistry(),
            .outputs = ArrayList(*Output).init(state.allocator),
            .seats = ArrayList(*Seat).init(state.allocator),
            .compositor = undefined,
            .subcompositor = undefined,
            .shm = undefined,
            .layerShell = undefined,
            .statusManager = undefined,
            .control = undefined,
            .globalsRegistered = mem.zeroes([6]bool),
        };
    }

    pub fn registerGlobals(self: *Wayland) !void {
        self.registry.setListener(*State, registryListener, self.state);
        _ = try self.display.roundtrip();

        for (self.globalsRegistered) |globalRegistered| {
            if (!globalRegistered) return error.UnsupportedGlobal;
        }
    }

    fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, state: *State) void {
        const wayland = &state.wayland;

        switch (event) {
            .global => |global| {
                const interface = global.interface;
                const name = global.name;

                if (strcmp(interface, wl.Compositor.getInterface().name) == 0) {
                    wayland.compositor = registry.bind(name, wl.Compositor, 4) catch return;
                    wayland.globalsRegistered[0] = true;
                } else if (strcmp(interface, wl.Subcompositor.getInterface().name) == 0) {
                    wayland.subcompositor = registry.bind(name, wl.Subcompositor, 1) catch return;
                    wayland.globalsRegistered[1] = true;
                } else if (strcmp(interface, wl.Shm.getInterface().name) == 0) {
                    wayland.shm = registry.bind(name, wl.Shm, 1) catch return;
                    wayland.globalsRegistered[2] = true;
                } else if (strcmp(interface, zwlr.LayerShellV1.getInterface().name) == 0) {
                    wayland.layerShell = registry.bind(name, zwlr.LayerShellV1, 1) catch return;
                    wayland.globalsRegistered[3] = true;
                } else if (strcmp(interface, zriver.StatusManagerV1.getInterface().name) == 0) {
                    wayland.statusManager = registry.bind(name, zriver.StatusManagerV1, 1) catch return;
                    wayland.globalsRegistered[4] = true;
                } else if (strcmp(interface, zriver.ControlV1.getInterface().name) == 0) {
                    wayland.control = registry.bind(name, zriver.ControlV1, 1) catch return;
                    wayland.globalsRegistered[5] = true;
                } else if (strcmp(interface, wl.Output.getInterface().name) == 0) {
                    const output = Output.create(state, registry, name) catch return;
                    wayland.outputs.append(output) catch return;
                } else if (strcmp(interface, wl.Seat.getInterface().name) == 0) {
                    const seat = Seat.create(state, registry, name) catch return;
                    wayland.seats.append(seat) catch return;
                }
            },
            .global_remove => |data| {
                for (wayland.outputs.items) |output, i| {
                    if (output.globalName == data.name) {
                        output.destroy();
                        _ = wayland.outputs.swapRemove(i);
                        break;
                    }
                }
                for (wayland.seats.items) |seat, i| {
                    if (seat.globalName == data.name) {
                        seat.destroy();
                        _ = wayland.seats.swapRemove(i);
                        break;
                    }
                }
            },
        }
    }

    pub fn findSurface(self: *Wayland, wlSurface: ?*wl.Surface) ?*Surface {
        if (wlSurface == null) {
            return null;
        }
        for (self.outputs.items) |output| {
            if (output.surface) |surface| {
                if (surface.backgroundSurface == wlSurface or
                    surface.tagsSurface == wlSurface or
                    surface.clockSurface == wlSurface or
                    surface.modulesSurface == wlSurface)
                {
                    return surface;
                }
            }
        }
        return null;
    }
};

pub const Output = struct {
    state: *State,
    wlOutput: *wl.Output,
    globalName: u32,
    scale: i32,

    surface: ?*Surface,
    tags: *Tags,

    pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Output {
        const self = try state.allocator.create(Output);
        self.state = state;
        self.wlOutput = try registry.bind(name, wl.Output, 3);
        self.globalName = name;
        self.scale = 1;

        self.surface = null;
        self.tags = try Tags.create(state, self);

        self.wlOutput.setListener(*Output, listener, self);
        return self;
    }

    pub fn destroy(self: *Output) void {
        if (self.surface) |surface| {
            surface.destroy();
        }
        self.tags.destroy();
        self.state.allocator.destroy(self);
    }

    fn listener(_: *wl.Output, event: wl.Output.Event, output: *Output) void {
        switch (event) {
            .scale => |scale| {
                output.scale = scale.factor;
            },
            .geometry => {},
            .mode => {},
            .name => {},
            .description => {},
            .done => {
                if (output.surface) |_| {} else {
                    output.surface = Surface.create(output) catch return;
                }
            },
        }
    }
};

pub const Seat = struct {
    state: *State,
    wlSeat: *wl.Seat,
    globalName: u32,

    pointer: struct {
        wlPointer: ?*wl.Pointer,
        x: i32,
        y: i32,
        surface: ?*Surface,
    },

    pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Seat {
        const self = try state.allocator.create(Seat);
        self.state = state;
        self.wlSeat = try registry.bind(name, wl.Seat, 3);
        self.globalName = name;

        self.pointer.wlPointer = null;
        self.pointer.surface = null;

        self.wlSeat.setListener(*Seat, listener, self);
        return self;
    }

    pub fn destroy(self: *Seat) void {
        if (self.pointer.wlPointer) |wlPointer| {
            wlPointer.release();
        }
        self.wlSeat.release();
        self.state.allocator.destroy(self);
    }

    fn listener(wlSeat: *wl.Seat, event: wl.Seat.Event, seat: *Seat) void {
        switch (event) {
            .capabilities => |data| {
                if (seat.pointer.wlPointer) |wlPointer| {
                    wlPointer.release();
                    seat.pointer.wlPointer = null;
                }
                if (data.capabilities.pointer) {
                    seat.pointer.wlPointer = wlSeat.getPointer() catch return;
                    seat.pointer.wlPointer.?.setListener(
                        *Seat,
                        pointerListener,
                        seat,
                    );
                }
            },
            .name => {},
        }
    }

    fn pointerListener(
        _: *wl.Pointer,
        event: wl.Pointer.Event,
        seat: *Seat,
    ) void {
        switch (event) {
            .enter => |data| {
                seat.pointer.x = data.surface_x.toInt();
                seat.pointer.y = data.surface_y.toInt();
                const surface = seat.state.wayland.findSurface(data.surface);
                seat.pointer.surface = surface;
            },
            .leave => |_| {
                seat.pointer.surface = null;
            },
            .motion => |data| {
                seat.pointer.x = data.surface_x.toInt();
                seat.pointer.y = data.surface_y.toInt();
            },
            .button => |data| {
                if (data.state != .pressed) return;
                if (seat.pointer.surface) |surface| {
                    if (!surface.configured) return;

                    const x = @intCast(u32, seat.pointer.x);
                    if (x < surface.height * 9) {
                        surface.output.tags.handleClick(x, seat) catch return;
                    }
                }
            },
            else => {},
        }
    }
};

pub const Surface = struct {
    output: *Output,

    backgroundSurface: *wl.Surface,
    layerSurface: *zwlr.LayerSurfaceV1,
    backgroundBuffers: [2]Buffer,

    tagsSurface: *wl.Surface,
    tagsSubsurface: *wl.Subsurface,
    tagsBuffers: [2]Buffer,

    clockSurface: *wl.Surface,
    clockSubsurface: *wl.Subsurface,
    clockBuffers: [2]Buffer,

    modulesSurface: *wl.Surface,
    modulesSubsurface: *wl.Subsurface,
    modulesBuffers: [2]Buffer,

    configured: bool,
    width: u16,
    height: u16,

    pub fn create(output: *Output) !*Surface {
        const state = output.state;
        const wayland = state.wayland;

        const self = try state.allocator.create(Surface);
        self.output = output;
        self.configured = false;

        self.backgroundSurface = try wayland.compositor.createSurface();
        self.layerSurface = try wayland.layerShell.getLayerSurface(
            self.backgroundSurface,
            output.wlOutput,
            .top,
            "levee",
        );
        self.backgroundBuffers = mem.zeroes([2]Buffer);

        self.tagsSurface = try wayland.compositor.createSurface();
        self.tagsSubsurface = try wayland.subcompositor.getSubsurface(
            self.tagsSurface,
            self.backgroundSurface,
        );
        self.tagsBuffers = mem.zeroes([2]Buffer);

        self.clockSurface = try wayland.compositor.createSurface();
        self.clockSubsurface = try wayland.subcompositor.getSubsurface(
            self.clockSurface,
            self.backgroundSurface,
        );
        self.clockBuffers = mem.zeroes([2]Buffer);

        self.modulesSurface = try wayland.compositor.createSurface();
        self.modulesSubsurface = try wayland.subcompositor.getSubsurface(
            self.modulesSurface,
            self.backgroundSurface,
        );
        self.modulesBuffers = mem.zeroes([2]Buffer);

        // setup layer surface
        self.layerSurface.setSize(0, state.config.height);
        self.layerSurface.setAnchor(
            .{ .top = true, .left = true, .right = true, .bottom = false },
        );
        self.layerSurface.setExclusiveZone(state.config.height);
        self.layerSurface.setMargin(0, 0, 0, 0);
        self.layerSurface.setListener(*Surface, layerSurfaceListener, self);

        // setup subsurfaces
        self.tagsSubsurface.setPosition(0, 0);
        self.clockSubsurface.setPosition(0, 0);
        self.modulesSubsurface.setPosition(0, 0);

        self.tagsSurface.commit();
        self.clockSurface.commit();
        self.backgroundSurface.commit();

        return self;
    }

    pub fn destroy(self: *Surface) void {
        self.output.surface = null;

        self.backgroundSurface.destroy();
        self.layerSurface.destroy();
        self.backgroundBuffers[0].deinit();
        self.backgroundBuffers[1].deinit();

        self.tagsSurface.destroy();
        self.tagsSubsurface.destroy();
        self.tagsBuffers[0].deinit();
        self.tagsBuffers[1].deinit();

        self.clockSurface.destroy();
        self.clockSubsurface.destroy();
        self.clockBuffers[0].deinit();
        self.clockBuffers[1].deinit();

        self.modulesSurface.destroy();
        self.modulesSubsurface.destroy();
        self.modulesBuffers[0].deinit();
        self.modulesBuffers[1].deinit();

        self.output.state.allocator.destroy(self);
    }

    fn layerSurfaceListener(
        layerSurface: *zwlr.LayerSurfaceV1,
        event: zwlr.LayerSurfaceV1.Event,
        surface: *Surface,
    ) void {
        switch (event) {
            .configure => |data| {
                surface.configured = true;
                surface.width = @intCast(u16, data.width);
                surface.height = @intCast(u16, data.height);

                layerSurface.ackConfigure(data.serial);

                render.renderBackground(surface) catch return;
                render.renderTags(surface) catch return;
                render.renderClock(surface) catch return;
                render.renderModules(surface) catch return;

                surface.tagsSurface.commit();
                surface.clockSurface.commit();
                surface.modulesSurface.commit();
                surface.backgroundSurface.commit();
            },
            .closed => {
                surface.destroy();
            },
        }
    }
};
