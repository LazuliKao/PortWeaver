const std = @import("std");
const uv = @import("../../uv.zig");
const common = @import("common.zig");

pub const ForwardError = common.ForwardError;

const c = uv.c;

const AllocatorContext = struct {
    allocator: std.mem.Allocator,

    fn alloc(ctx: ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *AllocatorContext = @ptrCast(@alignCast(ctx));
        const bytes = self.allocator.alloc(u8, size) catch return null;
        return @ptrCast(bytes.ptr);
    }

    fn free(ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
        const self: *AllocatorContext = @ptrCast(@alignCast(ctx));
        if (ptr) |p| {
            const slice: [*]u8 = @ptrCast(@alignCast(p));
            self.allocator.free(slice[0..1]);
        }
    }
};

pub const UdpForwarder = struct {
    allocator: std.mem.Allocator,
    listen_port: u16,
    target_address: []const u8,
    target_port: u16,
    family: common.AddressFamily,

    forwarder: ?*c.udp_forwarder_t = null,

    pub fn init(
        allocator: std.mem.Allocator,
        listen_port: u16,
        target_address: []const u8,
        target_port: u16,
        family: common.AddressFamily,
    ) UdpForwarder {
        return .{
            .allocator = allocator,
            .listen_port = listen_port,
            .target_address = target_address,
            .target_port = target_port,
            .family = family,
        };
    }

    pub fn deinit(self: *UdpForwarder) void {
        if (self.forwarder) |f| {
            c.udp_forwarder_destroy(f);
            self.forwarder = null;
        }
    }

    pub fn start(self: *UdpForwarder) !void {
        const target_host_z = try self.allocator.dupeZ(u8, self.target_address);
        defer self.allocator.free(target_host_z);

        const addr_family: c.addr_family_t = switch (self.family) {
            .ipv4 => c.ADDR_FAMILY_IPV4,
            .ipv6 => c.ADDR_FAMILY_IPV6,
            .any => c.ADDR_FAMILY_ANY,
        };

        const forwarder = c.udp_forwarder_create(self.listen_port, target_host_z.ptr, self.target_port, addr_family);
        if (forwarder == null) return ForwardError.ListenFailed;
        self.forwarder = forwarder;

        std.debug.print("[UDP] Listening on port {d}, forwarding to {s}:{d}\n", .{
            self.listen_port,
            self.target_address,
            self.target_port,
        });

        const rc = c.udp_forwarder_start(forwarder.?);
        if (rc != 0) return ForwardError.ListenFailed;
    }

    pub fn stop(self: *UdpForwarder) void {
        if (self.forwarder) |f| {
            c.udp_forwarder_stop(f);
        }
    }
};
