const std = @import("std");
const os = std.os;
const fs = std.fs;

const Cursor = struct {
    x: u32,
    y: u32,
};

const Readline = struct {
    const Self = @This();

    termios: os.termios,
    tty: fs.File,
    cursor: Cursor,
    prompt: []const u8,
    output: []u8,
    index: usize,

    pub fn init(tty: fs.File, promt: []const u8, output: []u8) !Self {
        const original_termios = try initTerminal(tty);
        return Self{
            .termios = original_termios,
            .tty = tty,
            .cursor = Cursor{ .x = 0, .y = 0 },
            .prompt = promt,
            .output = output,
            .index = 0,
        };
    }

    pub fn deinit(self: *Self) !void {
        try restoreTerminal(self.tty, self.termios);
    }

    pub fn start(self: *Self) !?usize {
        try self.refreshScreen();
        const writer = self.tty.writer();
        while (true) {
            var buffer: [1]u8 = undefined;
            _ = try self.tty.read(&buffer);

            switch (buffer[0]) {
                'q' => return null,
                '\x1b' => {
                    const bracket = try self.tty.reader().readByte();
                    const code = try self.tty.reader().readByte();
                    if (bracket == '[') {
                        switch (code) {
                            'A' => {},
                            'B' => {},
                            'C' => {},
                            'D' => {},
                            else => {},
                        }
                    }
                },
                '\r' => {
                    try writer.writeAll("\r\n");
                    break;
                },
                127 => {
                    if (self.index > 0) {
                        self.index -= 1;
                        try self.refreshScreen();
                    }
                },
                else => |byte| {
                    try writer.writeByte(byte);
                    self.output[self.index] = byte;
                    self.index += 1;
                },
            }
        }
        return self.index;
    }

    fn move(self: *Self, new_x: u32, new_y: u32) !void {
        self.cursor.x = new_x;
        self.cursor.y = new_y;
        _ = try self.tty.writer().print("\x1b[{};{}H", .{ self.cursor.y + 1, self.cursor.x + 1 });
    }

    fn refreshScreen(self: *Self) !void {
        const writer = self.tty.writer();

        const cursor: Point = blk: {
            try writer.writeAll("\x1b[6n");

            var buf: [8]u8 = undefined;
            const response = try self.tty.reader().readUntilDelimiter(&buf, 'R');

            const seperator = std.mem.indexOf(u8, response, ";").?;
            const line_str = response[2..seperator];
            const col_str = response[seperator + 1 ..];

            const line = try std.fmt.parseInt(u16, line_str, 10);
            const col = try std.fmt.parseInt(u16, col_str, 10);

            break :blk Point{
                .x = col,
                .y = line,
            };
        };

        // try writer.writeAll("\x1b[6n");
        try writer.print("\x1b[{};1H", .{cursor.y});
        try writer.writeAll("\x1b[2K");
        try writer.writeAll(self.prompt);
        try writer.writeAll(self.output[0..self.index]);
    }
};

fn initTerminal(tty: fs.File) !os.termios {
    const cooked_termios = try os.tcgetattr(tty.handle);
    errdefer restoreTerminal(tty, cooked_termios) catch {};

    var raw = cooked_termios;
    raw.lflag &= ~@as(
        os.system.tcflag_t,
        os.system.ECHO | os.system.ICANON | os.system.ISIG | os.system.IEXTEN,
    );
    raw.iflag &= ~@as(
        os.system.tcflag_t,
        os.system.IXON | os.system.ICRNL | os.system.BRKINT | os.system.INPCK | os.system.ISTRIP,
    );
    raw.oflag &= ~@as(os.system.tcflag_t, os.system.OPOST);
    raw.cflag |= os.system.CS8;
    raw.cc[os.system.V.TIME] = 0;
    raw.cc[os.system.V.MIN] = 1;
    try os.tcsetattr(tty.handle, .FLUSH, raw);

    return cooked_termios;
}

fn restoreTerminal(tty: fs.File, original_state: os.termios) !void {
    const writer = tty.writer();
    try writer.writeAll("\x1B[0m"); // Atribute reset
    try os.tcsetattr(tty.handle, .FLUSH, original_state);
}

const Point = struct {
    x: u16,
    y: u16,
};

pub fn readline(allocator: std.mem.Allocator, prompt: []const u8, output: []u8) !?usize {
    _ = output;
    _ = prompt;
    _ = allocator;
    var tty = try fs.cwd().openFile("/dev/tty", .{ .mode = .read_write });
    defer tty.close();

    var rl = try Readline.init(tty, prompt, output);
    defer rl.deinit() catch {};
    return try rl.start();
}
