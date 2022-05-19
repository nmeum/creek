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
mainloop: *pulse.pa_threaded_mainloop,
api: *pulse.pa_mainloop_api,
context: *pulse.pa_context,
fd: os.fd_t,
sink_name: []const u8,
sink_is_running: bool,
volume: u8,
muted: bool,

pub fn create(state: *State) !*Pulse {
    const self = try state.gpa.create(Pulse);
    self.state = state;
    self.volume = 0;
    self.muted = false;
    try self.initPulse();

    // create descriptor for poll in Loop
    const fd = try os.eventfd(0, os.linux.EFD.NONBLOCK);
    self.fd = @intCast(os.fd_t, fd);

    return self;
}

pub fn module(self: *Pulse) !Module {
    return Module{
        .impl = @ptrCast(*anyopaque, self),
        .funcs = .{
            .getEvent = getEvent,
            .print = print,
            .destroy = destroy,
        },
    };
}

fn getEvent(self_opaque: *anyopaque) !Event {
    const self = utils.cast(Pulse)(self_opaque);

    return Event{
        .fd = .{ .fd = self.fd, .events = os.POLL.IN, .revents = undefined },
        .data = self_opaque,
        .callbackIn = callbackIn,
        .callbackOut = Event.noop,
    };
}

fn print(self_opaque: *anyopaque, writer: Module.StringWriter) !void {
    const self = utils.cast(Pulse)(self_opaque);

    if (self.muted) {
        try writer.print("   🔇   ", .{});
    } else {
        try writer.print("🔊   {d}%", .{self.volume});
    }
}

fn callbackIn(self_opaque: *anyopaque) Event.Action {
    const self = utils.cast(Pulse)(self_opaque);

    var data = mem.zeroes([8]u8);
    _ = os.read(self.fd, &data) catch |err| {
        log.err("pulse: failed to read: {s}", .{@errorName(err)});
        return .terminate;
    };

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
    return .ok;
}

fn destroy(self_opaque: *anyopaque) void {
    const self = utils.cast(Pulse)(self_opaque);

    self.deinitPulse();
    self.state.gpa.destroy(self);
}

fn initPulse(self: *Pulse) !void {
    self.mainloop = pulse.pa_threaded_mainloop_new() orelse {
        return error.InitFailed;
    };
    self.api = pulse.pa_threaded_mainloop_get_api(self.mainloop);
    self.context = pulse.pa_context_new(self.api, "levee") orelse {
        return error.InitFailed;
    };
    const connected = pulse.pa_context_connect(
        self.context,
        null,
        pulse.PA_CONTEXT_NOFAIL,
        null,
    );
    if (connected < 0) return error.InitFailed;
    pulse.pa_context_set_state_callback(
        self.context,
        contextStateCallback,
        @ptrCast(*anyopaque, self),
    );
    const started = pulse.pa_threaded_mainloop_start(self.mainloop);
    if (started < 0) return error.InitFailed;
}

fn deinitPulse(self: *Pulse) void {
    if (self.api.quit) |quit| quit(self.api, 0);
    pulse.pa_threaded_mainloop_stop(self.mainloop);
    pulse.pa_threaded_mainloop_free(self.mainloop);
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
            self.deinitPulse();
            self.initPulse() catch return;
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
