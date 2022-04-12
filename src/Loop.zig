const std = @import("std");
const mem = std.mem;
const os = std.os;

const State = @import("main.zig").State;
const Loop = @This();

state: *State,
sfd: os.fd_t,

pub const Event = struct {
    fd: os.pollfd,
    data: *anyopaque,
    callbackIn: Callback,
    callbackOut: Callback,

    pub const Callback = fn (*anyopaque) error{Terminate}!void;

    pub fn terminate(_: *anyopaque) error{Terminate}!void {
        return error.Terminate;
    }

    pub fn noop(_: *anyopaque) error{Terminate}!void {
        return;
    }
};

pub fn init(state: *State) !Loop {
    var mask = mem.zeroes(os.linux.sigset_t);
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
            const ret = try display.dispatchPending();
            _ = try display.flush();
            if (ret <= 0) break;
        }
        _ = try os.poll(fds, -1);

        for (fds) |fd, i| {
            if (fd.revents & os.POLL.HUP != 0) return;
            if (fd.revents & os.POLL.ERR != 0) return;

            if (fd.revents & os.POLL.IN != 0) {
                const event = events.get(i);
                event.callbackIn(event.data) catch return;
            }
            if (fd.revents & os.POLL.OUT != 0) {
                const event = events.get(i);
                event.callbackOut(event.data) catch return;
            }
        }
    }
}
