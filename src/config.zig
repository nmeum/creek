const pixman = @import("pixman");

pub const Config = struct {
    height: u16,
    backgroundColor: pixman.Color,
    foregroundColor: pixman.Color,
    border: u15,

    pub fn init() Config {
        return Config{
            .height = 32,
            .backgroundColor = .{
                .red = 0,
                .green = 0,
                .blue = 0,
                .alpha = 0xffff,
            },
            .foregroundColor = .{
                .red = 0xffff,
                .green = 0xffff,
                .blue = 0xffff,
                .alpha = 0xffff,
            },
            .border = 2,
        };
    }
};
