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

pub const Wayland = struct {
    state: *State,
    display: *wl.Display,
    registry: *wl.Registry,

    outputs: ArrayList(*Output),

    compositor: *wl.Compositor,
    shm: *wl.Shm,
    layerShell: *zwlr.LayerShellV1,
    statusManager: *zriver.StatusManagerV1,

    globalsRegistered: [4]bool,

    pub fn init(state: *State) !Wayland {
        const display = try wl.Display.connect(null);

        return Wayland{
            .state = state,
            .display = display,
            .registry = try display.getRegistry(),
            .outputs = ArrayList(*Output).init(state.allocator),
            .compositor = undefined,
            .shm = undefined,
            .layerShell = undefined,
            .statusManager = undefined,
            .globalsRegistered = mem.zeroes([4]bool),
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
                } else if (strcmp(interface, wl.Shm.getInterface().name) == 0) {
                    wayland.shm = registry.bind(name, wl.Shm, 1) catch return;
                    wayland.globalsRegistered[1] = true;
                } else if (strcmp(interface, zwlr.LayerShellV1.getInterface().name) == 0) {
                    wayland.layerShell = registry.bind(name, zwlr.LayerShellV1, 1) catch return;
                    wayland.globalsRegistered[2] = true;
                } else if (strcmp(interface, zriver.StatusManagerV1.getInterface().name) == 0) {
                    wayland.statusManager = registry.bind(name, zriver.StatusManagerV1, 1) catch return;
                    wayland.globalsRegistered[3] = true;
                } else if (strcmp(interface, wl.Output.getInterface().name) == 0) {
                    const output = Output.create(state, registry, name) catch return;
                    wayland.outputs.append(output) catch return;
                }
            },
            .global_remove => |data| {
                for (wayland.outputs.items) |output, i| {
                    if (output.globalName == data.name) {
                        state.allocator.destroy(output);
                        _ = wayland.outputs.swapRemove(i);
                        break;
                    }
                }
            },
        }
    }
};

pub const Output = struct {
    state: *State,
    wlOutput: *wl.Output,
    globalName: u32,
    scale: i32,
    surface: ?*Surface,

    pub fn create(state: *State, registry: *wl.Registry, name: u32) !*Output {
        const self = try state.allocator.create(Output);
        self.state = state;
        self.wlOutput = try registry.bind(name, wl.Output, 3);
        self.globalName = name;
        self.scale = 1;
        self.surface = null;

        self.wlOutput.setListener(*Output, listener, self);
        return self;
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

pub const Surface = struct {
    output: *Output,

    backgroundSurface: *wl.Surface,
    backgroundBuffers: [2]Buffer,

    layerSurface: *zwlr.LayerSurfaceV1,

    configured: bool,
    width: u16,
    height: u16,

    pub fn create(output: *Output) !*Surface {
        const state = output.state;

        const self = try state.allocator.create(Surface);
        self.output = output;
        self.configured = false;

        self.backgroundSurface = try state.wayland.compositor.createSurface();
        self.backgroundBuffers = mem.zeroes([2]Buffer);

        self.layerSurface = try state.wayland.layerShell.getLayerSurface(
            self.backgroundSurface,
            output.wlOutput,
            .overlay,
            "levee",
        );

        const height = 32;
        self.layerSurface.setSize(0, height);
        self.layerSurface.setAnchor(
            .{ .top = true, .left = true, .right = true, .bottom = false },
        );
        self.layerSurface.setExclusiveZone(@intCast(i32, height));
        self.layerSurface.setMargin(0, 0, 0, 0);
        self.layerSurface.setListener(*Surface, layerSurfaceListener, self);

        self.backgroundSurface.commit();

        return self;
    }

    pub fn destroy(self: *Surface) void {
        self.output.surface = null;
        self.backgroundSurface.destroy();
        self.layerSurface.destroy();
        self.backgroundBuffers[0].deinit();
        self.backgroundBuffers[1].deinit();
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
                surface.backgroundSurface.commit();
            },
            .closed => {
                surface.destroy();
            },
        }
    }
};
