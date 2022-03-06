const std = @import("std");
const ansi = @import("ansi-term");
const os = std.os;
const fs = std.fs;

const ControlCode = union(enum) {
    newline,
    backspace,
    end_of_file,
    escape,
    left,
    right,
    up,
    down,
    character: u8,

    fn fromReader(reader: anytype) !ControlCode {
        const byte = try reader.readByte();
        switch (byte) {
            'q' => return .end_of_file,
            '\x1b' => {
                const bracket = try reader.readByte();
                const code = try reader.readByte();
                if (bracket == '[') {
                    switch (code) {
                        'A' => return .up,
                        'B' => return .down,
                        'C' => return .right,
                        'D' => return .left,
                        else => return error.UnimplementedControlCode,
                    }
                }
                return .escape;
            },
            '\r' => return .newline,
            127 => return .backspace,
            else => |char| return ControlCode{ .character = char },
        }
        unreachable;
    }
};

const Readline = struct {
    const Self = @This();

    termios: os.termios,
    tty: fs.File,
    cursor: ansi.Cursor,
    prompt: []const u8,
    output: []u8,
    index: usize,
    line_legth: usize,

    pub fn init(tty: fs.File, promt: []const u8, output: []u8) !Self {
        const original_termios = try initTerminal(tty);
        return Self{
            .termios = original_termios,
            .tty = tty,
            .cursor = ansi.Cursor{ .x = 0, .y = 0 },
            .prompt = promt,
            .output = output,
            .index = 0,
            .line_legth = 0,
        };
    }

    pub fn deinit(self: *Self) !void {
        try restoreTerminal(self.tty, self.termios);
    }

    pub fn start(self: *Self) !?usize {
        try self.refreshScreen();
        const writer = self.tty.writer();
        while (true) {
            const code = try ControlCode.fromReader(self.tty.reader());
            switch (code) {
                .escape, .end_of_file => return null,
                .backspace => {
                    if (self.index > 0) {
                        self.index -= 1;
                        try self.refreshScreen();
                    }
                },
                .newline => {
                    try writer.writeAll("\r\n");
                    break;
                },
                .up => {},
                .down => {},
                .left => {
                    const cursor = try ansi.getCursor(writer, self.tty);
                    if (cursor.x > self.prompt.len + 1) {
                        try ansi.cursorBackward(writer, 1);

                        if (self.index > 0)
                            self.index -= 1;
                    }
                    //> |
                },
                .right => {
                    const cursor = try ansi.getCursor(writer, self.tty);
                    if (cursor.x <= self.index + self.prompt.len) {
                        try ansi.cursorForward(writer, 1);
                        self.index += 1;
                    }
                },
                .character => |char| {
                    if (self.line_legth + 1 >= self.output.len) {
                        return error.LineLengthExceeded;
                    }
                    if (self.line_legth == self.index) {
                        self.output[self.line_legth] = char;
                    } else {
                        var i: usize = self.line_legth;
                        while (i > self.index) : (i -= 1) {
                            self.output[i] = self.output[i - 1];
                        }
                        self.output[self.index] = char;
                    }
                    self.index += 1;
                    self.line_legth += 1;
                    try self.refreshScreen();
                },
            }
        }
        return self.line_legth;
    }

    fn moveCursor(self: *Self, new_x: i32, new_y: i32) !void {
        if (new_x < 0) {
            self.cursor.x = 0;
        } else {
            self.cursor.x = @intCast(u16, new_x);
        }
        if (new_y < 0) {
            self.cursor.y = 0;
        } else {
            self.cursor.y = @intCast(u16, new_y);
        }
        try ansi.setCursor(self.tty.writer(), self.cursor.x, self.cursor.y);
    }

    fn moveCursorRel(self: *Self, x: i32, y: i32) !void {
        try self.moveCursor(self.cursor.x + x, self.cursor.y + y);
    }

    fn refreshScreen(self: *Self) !void {
        const writer = self.tty.writer();

        const cursor = try ansi.getCursor(writer, self.tty);

        try writer.print("\x1b[{};1H", .{cursor.y});
        try writer.writeAll("\x1b[2K");
        try writer.writeAll(self.prompt);
        try writer.writeAll(self.output[0..self.line_legth]);

        self.cursor = try ansi.getCursor(writer, self.tty);
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
