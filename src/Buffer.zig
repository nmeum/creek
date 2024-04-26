const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const linux = std.os.linux;

const pixman = @import("pixman");
const wl = @import("wayland").client.wl;

const Buffer = @This();

mmap: ?[]align(4096) u8 = null,
data: ?[]u32 = null,
buffer: ?*wl.Buffer = null,
pix: ?*pixman.Image = null,

busy: bool = false,
width: u31 = 0,
height: u31 = 0,
size: u31 = 0,

pub fn resize(self: *Buffer, shm: *wl.Shm, width: u31, height: u31) !void {
    if (width == 0 or height == 0) return;

    self.busy = true;
    self.width = width;
    self.height = height;

    const fd = try posix.memfd_create("creek-shm", linux.MFD.CLOEXEC);
    defer posix.close(fd);

    const stride = width * 4;
    self.size = stride * height;
    try posix.ftruncate(fd, self.size);

    self.mmap = try posix.mmap(null, self.size, posix.PROT.READ | posix.PROT.WRITE, .{ .TYPE = .SHARED }, fd, 0);
    self.data = mem.bytesAsSlice(u32, self.mmap.?);

    const pool = try shm.createPool(fd, self.size);
    defer pool.destroy();

    self.buffer = try pool.createBuffer(0, width, height, stride, .argb8888);
    errdefer self.buffer.?.destroy();
    self.buffer.?.setListener(*Buffer, listener, self);

    self.pix = pixman.Image.createBitsNoClear(.a8r8g8b8, width, height, self.data.?.ptr, stride);
}

pub fn deinit(self: *Buffer) void {
    if (self.pix) |pix| _ = pix.unref();
    if (self.buffer) |buf| buf.destroy();
    if (self.mmap) |mmap| posix.munmap(mmap);
}

fn listener(_: *wl.Buffer, event: wl.Buffer.Event, buffer: *Buffer) void {
    switch (event) {
        .release => buffer.busy = false,
    }
}

pub fn nextBuffer(pool: *[2]Buffer, shm: *wl.Shm, width: u16, height: u16) !*Buffer {
    if (pool[0].busy and pool[1].busy) {
        return error.NoAvailableBuffers;
    }
    const buffer = if (!pool[0].busy) &pool[0] else &pool[1];

    if (buffer.width != width or buffer.height != height) {
        buffer.deinit();
        try buffer.resize(shm, width, height);
    }
    return buffer;
}
