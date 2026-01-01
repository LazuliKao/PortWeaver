const std = @import("std");
const uv = @import("uv.zig");
const common = @import("common.zig");

pub const ForwardError = common.ForwardError;

const c = uv.c;

pub const UdpForwarder = struct {
    allocator: std.mem.Allocator,
    listen_port: u16,
    target_address: []const u8,
    target_port: u16,
    family: common.AddressFamily,
    enable_stats: bool,

    forwarder: ?*c.udp_forwarder_t = null,

    pub fn init(
        allocator: std.mem.Allocator,
        listen_port: u16,
        target_address: []const u8,
        target_port: u16,
        family: common.AddressFamily,
        enable_stats: bool,
    ) UdpForwarder {
        return .{
            .allocator = allocator,
            .listen_port = listen_port,
            .target_address = target_address,
            .target_port = target_port,
            .family = family,
            .enable_stats = enable_stats,
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

        const forwarder = c.udp_forwarder_create(
            self.listen_port,
            target_host_z.ptr,
            self.target_port,
            addr_family,
            if (self.enable_stats) 1 else 0,
        );
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

    pub fn getHandle(self: *UdpForwarder) ?*c.udp_forwarder_t {
        return self.forwarder;
    }

    pub fn getStats(self: *UdpForwarder) common.TrafficStats {
        if (self.forwarder) |f| {
            const c_stats = c.udp_forwarder_get_stats(f);
            return .{
                .bytes_in = c_stats.bytes_in,
                .bytes_out = c_stats.bytes_out,
            };
        }
        return .{ .bytes_in = 0, .bytes_out = 0 };
    }
};

pub fn getStatsRaw(fwd: *c.udp_forwarder_t) common.TrafficStats {
    const c_stats = c.udp_forwarder_get_stats(fwd);
    return .{ .bytes_in = c_stats.bytes_in, .bytes_out = c_stats.bytes_out };
}
