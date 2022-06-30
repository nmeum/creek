const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;

const pulse = @cImport(@cInclude("pulse/pulseaudio.h"));

const Module = @import("../Modules.zig").Module;
const Event = @import("../Loop.zig").Event;
const render = @import("../render.zig");
const State = @import("../main.zig").State;
const utils = @import("../utils.zig");
const Pulse = @This();

state: *State,
fd: os.fd_t,
mainloop: *pulse.pa_threaded_mainloop,
api: *pulse.pa_mainloop_api,
context: *pulse.pa_context,
// owned by pulse api
sink_name: []const u8,
sink_is_running: bool,
volume: u8,
muted: bool,

pub fn init(state: *State) !Pulse {
    // create descriptor for poll in Loop
    const efd = efd: {
        const fd = try os.eventfd(0, os.linux.EFD.NONBLOCK);
        break :efd @intCast(os.fd_t, fd);
    };

    // setup pulseaudio api
    const mainloop = pulse.pa_threaded_mainloop_new() orelse {
        return error.InitFailed;
    };
    const api = pulse.pa_threaded_mainloop_get_api(mainloop);
    const context = pulse.pa_context_new(api, "levee") orelse {
        return error.InitFailed;
    };
    const connected = pulse.pa_context_connect(context, null, pulse.PA_CONTEXT_NOFAIL, null);
    if (connected < 0) return error.InitFailed;

    return Pulse{
        .state = state,
        .fd = efd,
        .mainloop = mainloop,
        .api = api,
        .context = context,
        .sink_name = "",
        .sink_is_running = false,
        .volume = 0,
        .muted = false,
    };
}

pub fn deinit(self: *Pulse) void {
    if (self.api.quit) |quit| quit(self.api, 0);
    pulse.pa_threaded_mainloop_stop(self.mainloop);
    pulse.pa_threaded_mainloop_free(self.mainloop);
}

pub fn start(self: *Pulse) !void {
    pulse.pa_context_set_state_callback(
        self.context,
        contextStateCallback,
        @ptrCast(*anyopaque, self),
    );
    const started = pulse.pa_threaded_mainloop_start(self.mainloop);
    if (started < 0) return error.StartFailed;
}

pub fn refresh(self: *Pulse) !void {
    var data = mem.zeroes([8]u8);
    _ = try os.read(self.fd, &data);

    for (self.state.wayland.monitors.items) |monitor| {
        if (monitor.bar) |bar| {
            if (bar.configured) {
                render.renderClock(bar) catch continue;
                render.renderModules(bar) catch continue;
                bar.clock.surface.commit();
                bar.modules.surface.commit();
                bar.background.surface.commit();
            }
        }
    }
}

pub fn print(self: *Pulse, writer: anytype) !void {
    if (self.muted) {
        try writer.print("   🔇   ", .{});
    } else {
        try writer.print("🔊   {d}%", .{self.volume});
    }
}

export fn contextStateCallback(
    ctx: ?*pulse.pa_context,
    self_opaque: ?*anyopaque,
) void {
    const self = utils.cast(Pulse)(self_opaque.?);

    const ctx_state = pulse.pa_context_get_state(ctx);
    switch (ctx_state) {
        pulse.PA_CONTEXT_READY => {
            _ = pulse.pa_context_get_server_info(
                ctx,
                serverInfoCallback,
                self_opaque,
            );
            pulse.pa_context_set_subscribe_callback(
                ctx,
                subscribeCallback,
                self_opaque,
            );
            const mask = pulse.PA_SUBSCRIPTION_MASK_SERVER |
                pulse.PA_SUBSCRIPTION_MASK_SINK |
                pulse.PA_SUBSCRIPTION_MASK_SINK_INPUT |
                pulse.PA_SUBSCRIPTION_MASK_SOURCE |
                pulse.PA_SUBSCRIPTION_MASK_SOURCE_OUTPUT;
            _ = pulse.pa_context_subscribe(ctx, mask, null, null);
        },
        pulse.PA_CONTEXT_TERMINATED, pulse.PA_CONTEXT_FAILED => {
            log.info("pulse: restarting", .{});
            self.deinit();
            self.* = Pulse.init(self.state) catch return;
            log.info("pulse: restarted", .{});
        },
        else => {},
    }
}

export fn serverInfoCallback(
    ctx: ?*pulse.pa_context,
    info: ?*const pulse.pa_server_info,
    self_opaque: ?*anyopaque,
) void {
    const self = utils.cast(Pulse)(self_opaque.?);

    self.sink_name = mem.span(info.?.default_sink_name);
    self.sink_is_running = true;
    log.info("pulse: sink set to {s}", .{self.sink_name});

    _ = pulse.pa_context_get_sink_info_list(ctx, sinkInfoCallback, self_opaque);
}

export fn subscribeCallback(
    ctx: ?*pulse.pa_context,
    event_type: pulse.pa_subscription_event_type_t,
    index: u32,
    self_opaque: ?*anyopaque,
) void {
    const operation = event_type & pulse.PA_SUBSCRIPTION_EVENT_TYPE_MASK;
    if (operation != pulse.PA_SUBSCRIPTION_EVENT_CHANGE) return;

    const facility = event_type & pulse.PA_SUBSCRIPTION_EVENT_FACILITY_MASK;
    if (facility == pulse.PA_SUBSCRIPTION_EVENT_SINK) {
        _ = pulse.pa_context_get_sink_info_by_index(
            ctx,
            index,
            sinkInfoCallback,
            self_opaque,
        );
    }
}

export fn sinkInfoCallback(
    _: ?*pulse.pa_context,
    maybe_info: ?*const pulse.pa_sink_info,
    _: c_int,
    self_opaque: ?*anyopaque,
) void {
    const self = utils.cast(Pulse)(self_opaque.?);
    const info = maybe_info orelse return;

    const sink_name = mem.span(info.name);
    const is_current = mem.eql(u8, self.sink_name, sink_name);
    const is_running = info.state == pulse.PA_SINK_RUNNING;

    if (is_current) self.sink_is_running = is_running;

    if (!self.sink_is_running and is_running) {
        self.sink_name = sink_name;
        self.sink_is_running = true;
        log.info("pulse: sink set to {s}", .{sink_name});
    }

    self.volume = volume: {
        const avg = pulse.pa_cvolume_avg(&info.volume);
        const norm = @intToFloat(f64, pulse.PA_VOLUME_NORM);
        const ratio = 100 * @intToFloat(f64, avg) / norm;
        break :volume @floatToInt(u8, @round(ratio));
    };
    self.muted = info.mute != 0;

    const increment = mem.asBytes(&@as(u64, 1));
    _ = os.write(self.fd, increment) catch return;
}
