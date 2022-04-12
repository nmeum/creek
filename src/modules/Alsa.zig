const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const os = std.os;

const alsa = @cImport(@cInclude("alsa/asoundlib.h"));

const Module = @import("../Modules.zig").Module;
const Event = @import("../Loop.zig").Event;
const render = @import("../render.zig");
const State = @import("../main.zig").State;
const utils = @import("../utils.zig");
const Alsa = @This();

state: *State,
devices: DeviceList,

const Device = struct {
    ctl: *alsa.snd_ctl_t,
    name: []const u8,
};

const DeviceList = std.ArrayList(Device);

pub fn create(state: *State) !*Alsa {
    const self = try state.gpa.create(Alsa);
    self.* = .{
        .state = state,
        .devices = DeviceList.init(state.gpa),
    };

    var card: i32 = -1;
    while(alsa.snd_card_next(&card) >= 0 and card >= 0) {
        const name = try fmt.allocPrintZ(state.gpa, "hw:{d}", .{ card });

        var ctl: ?*alsa.snd_ctl_t = null;
        _ = alsa.snd_ctl_open(&ctl, name.ptr, alsa.SND_CTL_READONLY);
        _ = alsa.snd_ctl_subscribe_events(ctl, 1);

        try self.devices.append(.{ .ctl = ctl.?, .name = name });
    }

    return self;
}

pub fn module(self: *Alsa) !Module {
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
    const self = utils.cast(Alsa)(self_opaque);

    var fd = mem.zeroes(alsa.pollfd);
    const device = &self.devices.items[0];
    _ = alsa.snd_ctl_poll_descriptors(device.ctl, &fd, 1);

    return Event{
        .fd = @bitCast(os.pollfd, fd),
        .data = self_opaque,
        .callbackIn = callbackIn,
        .callbackOut = Event.noop,
    };
}

fn print(self_opaque: *anyopaque, writer: Module.StringWriter) !void {
    const self = utils.cast(Alsa)(self_opaque);
    _ = self;

    var handle: ?*alsa.snd_mixer_t = null;
    _ = alsa.snd_mixer_open(&handle, 0);
    _ = alsa.snd_mixer_attach(handle, "default");
    _ = alsa.snd_mixer_selem_register(handle, null, null);
    _ = alsa.snd_mixer_load(handle);

    var sid: ?*alsa.snd_mixer_selem_id_t = null;
    _ = alsa.snd_mixer_selem_id_malloc(&sid);
    defer alsa.snd_mixer_selem_id_free(sid);
    alsa.snd_mixer_selem_id_set_index(sid, 0);
    alsa.snd_mixer_selem_id_set_name(sid, "Master");
    const elem = alsa.snd_mixer_find_selem(handle, sid);

    var unmuted: i32 = 0;
    _ = alsa.snd_mixer_selem_get_playback_switch(
        elem,
        alsa.SND_MIXER_SCHN_MONO,
        &unmuted,
    );
    if (unmuted == 0) {
        return writer.print("   🔇   ", .{});
    }

    var min: i64 = 0;
    var max: i64 = 0;
    _ = alsa.snd_mixer_selem_get_playback_volume_range(elem, &min, &max);

    var volume: i64 = 0;
    _ = alsa.snd_mixer_selem_get_playback_volume(
        elem,
        alsa.SND_MIXER_SCHN_MONO,
        &volume,
    );

    const percent = percent: {
        var x = @intToFloat(f64, volume) / @intToFloat(f64, max);
        x = math.tanh(math.sqrt(x) * 0.65) * 180.0;
        break :percent @floatToInt(u8, @round(x));
    };
    return writer.print("🔊   {d}%", .{ percent });
}

fn callbackIn(self_opaque: *anyopaque) error{Terminate}!void {
    const self = utils.cast(Alsa)(self_opaque);

    var event: ?*alsa.snd_ctl_event_t = null;
    _ = alsa.snd_ctl_event_malloc(&event);
    defer alsa.snd_ctl_event_free(event);

    const device = &self.devices.items[0];
    _ = alsa.snd_ctl_read(device.ctl, event);

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

fn destroy(self_opaque: *anyopaque) void {
    const self = utils.cast(Alsa)(self_opaque);

    for (self.devices.items) |*device| {
        self.state.gpa.free(device.name);
    }
    self.devices.deinit();
    self.state.gpa.destroy(self);
}
