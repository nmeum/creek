const std = @import("std");
const mem = std.mem;
const os = std.os;

const wayland = @import("wayland").client;
const wl = wayland.wl;

const pixman = @import("pixman");

pub const Buffer = struct {
    data: ?[]align(4096) u8,
    buffer: ?*wl.Buffer,
    pix: ?*pixman.Image,

    busy: bool,
    width: u31,
    height: u31,
    size: u31,

    pub fn init(self: *Buffer, shm: *wl.Shm, width: u31, height: u31) !void {
        self.busy = true;
        self.width = width;
        self.height = height;

        const fd = try os.memfd_create("levee-wayland-shm-buffer-pool", 0);
        defer os.close(fd);

        const stride = width * 4;
        self.size = stride * height;
        try os.ftruncate(fd, self.size);

        self.data = try os.mmap(null, self.size, os.PROT.READ | os.PROT.WRITE, os.MAP.SHARED, fd, 0);
        errdefer os.munmap(self.data.?);

        const pool = try shm.createPool(fd, self.size);
        defer pool.destroy();

        self.buffer = try pool.createBuffer(0, width, height, stride, .argb8888);
        errdefer self.buffer.?.destroy();
        self.buffer.?.setListener(*Buffer, listener, self);

        self.pix = pixman.Image.createBitsNoClear(.a8r8g8b8, width, height, @ptrCast([*c]u32, self.data.?), stride);
    }

    pub fn deinit(self: *Buffer) void {
        if (self.pix) |pix| _ = pix.unref();
        if (self.buffer) |buf| buf.destroy();
        if (self.data) |data| os.munmap(data);
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
            try buffer.init(shm, width, height);
        }
        return buffer;
    }
};
