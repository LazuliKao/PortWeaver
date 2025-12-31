const std = @import("std");
const uv = @import("../../uv.zig");
const common = @import("common.zig");

pub const ForwardError = common.ForwardError;

const c = uv.c;

// Allocator wrapper for C
const AllocatorContext = struct {
    allocator: std.mem.Allocator,

    fn alloc(ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *AllocatorContext = @ptrCast(@alignCast(ctx));
        const bytes = self.allocator.alloc(u8, size) catch return null;
        return @ptrCast(bytes.ptr);
    }

    fn free(ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
        const self: *AllocatorContext = @ptrCast(@alignCast(ctx.?));
        if (ptr) |p| {
            const slice = @as([*]u8, @ptrCast(p))[0..1];
            self.allocator.free(slice);
        }
    }
};

pub const TcpForwarder = struct {
    allocator: std.mem.Allocator,
    forwarder: *c.tcp_forwarder_t,

    pub fn init(
        allocator: std.mem.Allocator,
        listen_port: u16,
        target_address: []const u8,
        target_port: u16,
        family: common.AddressFamily,
    ) TcpForwarder {
        var self: TcpForwarder = undefined;
        self.allocator = allocator;

        const target_z = allocator.dupeZ(u8, target_address) catch unreachable;
        defer allocator.free(target_z);

        const c_family: c.addr_family_t = switch (family) {
            .ipv4 => c.ADDR_FAMILY_IPV4,
            .ipv6 => c.ADDR_FAMILY_IPV6,
            .any => c.ADDR_FAMILY_ANY,
        };

        self.forwarder = c.tcp_forwarder_create(
            listen_port,
            target_z.ptr,
            target_port,
            c_family,
        ) orelse unreachable;

        return self;
    }

    pub fn start(self: *TcpForwarder) !void {
        if (c.tcp_forwarder_start(self.forwarder) != 0) {
            return ForwardError.ListenFailed;
        }
    }

    pub fn stop(self: *TcpForwarder) void {
        c.tcp_forwarder_stop(self.forwarder);
    }

    pub fn deinit(self: *TcpForwarder) void {
        c.tcp_forwarder_destroy(self.forwarder);
    }
};
