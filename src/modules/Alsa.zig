const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const mem = std.mem;
const os = std.os;

const alsa = @cImport(@cInclude("alsa/asoundlib.h"));

const Module = @import("../modules.zig").Module;
const Event = @import("../Loop.zig").Event;
const render = @import("../render.zig");
const State = @import("../main.zig").State;
const utils = @import("../utils.zig");
const Alsa = @This();

state: *State,
context: *alsa.snd_ctl_t,

pub fn init(state: *State) !Alsa {
    return Alsa{
        .state = state,
        .context = try getAlsaCtl(state.gpa),
    };
}

pub fn module(self: *Alsa) Module {
    return .{
        .impl = @ptrCast(*anyopaque, self),
        .eventFn = getEvent,
        .printFn = print,
    };
}

fn getEvent(self_opaque: *anyopaque) !Event {
    const self = utils.cast(Alsa)(self_opaque);

    var fd = mem.zeroes(alsa.pollfd);
    _ = alsa.snd_ctl_poll_descriptors(self.context, &fd, 1);

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
    _ = elem;

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
    _ = alsa.snd_ctl_read(self.context, event);

    for (self.state.wayland.monitors.items) |monitor| {
        if (monitor.surface) |surface| {
            if (surface.configured) {
                render.renderClock(surface) catch continue;
                render.renderModules(surface) catch continue;
                surface.clockSurface.commit();
                surface.modulesSurface.commit();
                surface.backgroundSurface.commit();
            }
        }
    }
}

fn getAlsaCtl(gpa: mem.Allocator) !*alsa.snd_ctl_t {
    var card: i32 = -1;
    _ = alsa.snd_card_next(&card);
    const name = try fmt.allocPrintZ(gpa, "hw:{d}", .{ card });
    defer gpa.free(name);

    var ctl: ?*alsa.snd_ctl_t = null;
    _ = alsa.snd_ctl_open(&ctl, name.ptr, alsa.SND_CTL_READONLY);
    _ = alsa.snd_ctl_subscribe_events(ctl, 1);

    return ctl.?;
}
