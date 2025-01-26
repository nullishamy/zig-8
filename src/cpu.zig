const std = @import("std");

pub const Registers = struct {
    const COUNT = 16;
    data: [COUNT]u8,

    // The 16-bit address register I is used with operations related to reading and writing memory.
    addr_reg: u16,

    // Used to store the result after the CPU awakes
    wake_reg: u8,

    pub fn get(self: *Registers, index: u8) u8 {
        return self.data[index];
    }

    pub fn set(self: *Registers, index: u8, value: u8) void {
        self.data[index] = value;
    }
};

const digits: [0x50]u8 = .{
    0xF0, 0x90, 0x90, 0x90, 0xF0, 0x20, 0x60, 0x20, 0x20, 0x70, 0xF0, 0x10, 0xF0, 0x80, 0xF0, 0xF0,
    0x10, 0xF0, 0x10, 0xF0, 0x90, 0x90, 0xF0, 0x10, 0x10, 0xF0, 0x80, 0xF0, 0x10, 0xF0, 0xF0, 0x80,
    0xF0, 0x90, 0xF0, 0xF0, 0x10, 0x20, 0x40, 0x40, 0xF0, 0x90, 0xF0, 0x90, 0xF0, 0xF0, 0x90, 0xF0,
    0x10, 0xF0, 0xF0, 0x90, 0xF0, 0x90, 0x90, 0xE0, 0x90, 0xE0, 0x90, 0xE0, 0xF0, 0x80, 0x80, 0x80,
    0xF0, 0xE0, 0x90, 0x90, 0x90, 0xE0, 0xF0, 0x80, 0xF0, 0x80, 0xF0, 0xF0, 0x80, 0xF0, 0x80, 0x80,
};

pub const RAM = struct {
    // Top of address range
    const CAPACITY = 0x1000;
    data: [CAPACITY]u8,

    pub fn get(self: *RAM, addr: u16) u8 {
        return self.data[addr];
    }

    pub fn set(self: *RAM, addr: u16, value: u8) void {
        self.data[addr] = value;
    }

    fn init(self: *RAM) void {
        for (digits, 0..) |digit, idx| {
            self.set(idx, digit);
        }
    }
};

pub const Timers = struct {
    delay: u8,

    pub fn tick(self: *Timers) void {
        if (self.delay >= 1) {
            self.delay -= 1;
        }
    }
};

pub const Keys = struct {
    data: [16]bool,

    pub fn pressed(self: *Keys, key: u8) bool {
        return self.data[key];
    }

    pub fn down(self: *Keys, key: u8) void{
        self.data[key] = true;
    }
    
    pub fn up(self: *Keys, key: u8) void{
        self.data[key] = false;
    }
};

pub const CPU = struct {
    pub const State = enum {
        wait_for_key,
        run
    };
    
    pub const ROM_BASE = 0x200;
    
    regs: Registers,
    timers: Timers,
    keys: Keys,
    ram: RAM,
    state: State,
    return_stack: std.ArrayList(u16),
    ip: u16,

    pub fn fetch_instruction(self: *CPU) u16 {
        const instBuf = [_]u8{ self.ram.get(self.ip), self.ram.get(self.ip + 1) };
        self.ip += 2;
        return std.mem.readInt(u16, &instBuf, .big);
    }

    pub fn new(alloc: std.mem.Allocator) CPU {
        return CPU{
            .state = .run,
            .regs = Registers{
                .data = std.mem.zeroes([Registers.COUNT]u8),
                .addr_reg = 0,
                .wake_reg = 0,
            },
            .timers = Timers {
                .delay = 0,
            },
            .keys = Keys {
                .data = std.mem.zeroes([16]bool),
            },
            .return_stack = std.ArrayList(u16).init(alloc),
            .ip = ROM_BASE,
            .ram = RAM{
                .data = std.mem.zeroes([RAM.CAPACITY]u8),
            }
        };
    }
};
