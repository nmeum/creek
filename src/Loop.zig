const std = @import("std");
const log = std.log;
const mem = std.mem;
const os = std.os;

const State = @import("main.zig").State;
const utils = @import("utils.zig");
const Loop = @This();

state: *State,
sfd: os.fd_t,

pub const Event = struct {
    fd: os.pollfd,
    data: *anyopaque,
    callbackIn: Callback,
    callbackOut: Callback,

    pub const Action = enum { ok, terminate };
    pub const Callback = fn (*anyopaque) Action;

    pub fn terminate(_: *anyopaque) Action {
        return .terminate;
    }

    pub fn noop(_: *anyopaque) Action {
        return .ok;
    }
};

pub fn init(state: *State) !Loop {
    var mask = os.empty_sigset;
    os.linux.sigaddset(&mask, os.linux.SIG.INT);
    os.linux.sigaddset(&mask, os.linux.SIG.TERM);
    os.linux.sigaddset(&mask, os.linux.SIG.QUIT);

    _ = os.linux.sigprocmask(os.linux.SIG.BLOCK, &mask, null);
    const sfd = os.linux.signalfd(-1, &mask, os.linux.SFD.NONBLOCK);

    return Loop{ .state = state, .sfd = @intCast(os.fd_t, sfd) };
}

pub fn run(self: *Loop) !void {
    const gpa = self.state.gpa;
    const display = self.state.wayland.display;

    var events: std.MultiArrayList(Event) = .{};
    defer events.deinit(gpa);

    try events.append(gpa, .{
        .fd = .{ .fd = self.sfd, .events = os.POLL.IN, .revents = 0 },
        .data = undefined,
        .callbackIn = Event.terminate,
        .callbackOut = Event.noop,
    });
    try events.append(gpa, try self.state.wayland.getEvent());
    for (self.state.modules.modules.items) |*module| {
        try events.append(gpa, try module.getEvent());
    }

    const fds = events.items(.fd);
    while (true) {
        while (true) {
            const ret = display.dispatchPending();
            _ = display.flush();
            if (ret == .SUCCESS) break;
        }

        _ = os.poll(fds, -1) catch |err| {
            log.err("poll failed: {s}", .{@errorName(err)});
            return;
        };

        for (fds) |fd, i| {
            if (fd.revents & os.POLL.HUP != 0) return;
            if (fd.revents & os.POLL.ERR != 0) return;

            if (fd.revents & os.POLL.IN != 0) {
                const event = events.get(i);
                const action = event.callbackIn(event.data);
                switch (action) {
                    .ok => {},
                    .terminate => return,
                }
            }
            if (fd.revents & os.POLL.OUT != 0) {
                const event = events.get(i);
                const action = event.callbackOut(event.data);
                switch (action) {
                    .ok => {},
                    .terminate => return,
                }
            }
        }
    }
}
