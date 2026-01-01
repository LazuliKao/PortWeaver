const std = @import("std");
const types = @import("../config/types.zig");
const server = @import("../ubus/server.zig");

const common = @import("app_forward/common.zig");
const tcp_uv = @import("app_forward/tcp_forwarder_uv.zig");
const udp_uv = @import("app_forward/udp_forwarder_uv.zig");
const c = @import("app_forward/uv.zig").c;

pub const ForwardError = common.ForwardError;

pub inline fn getThreadConfig() std.Thread.SpawnConfig {
    return common.getThreadConfig();
}

pub const TcpForwarder = tcp_uv.TcpForwarder;
pub const UdpForwarder = udp_uv.UdpForwarder;

const ProjectHandles = struct {
    tcp: ?*c.tcp_forwarder_t = null,
    udp: ?*c.udp_forwarder_t = null,
};

var g_handles_items: [256]ProjectHandles = [_]ProjectHandles{.{}} ** 256;
var g_handles_len: usize = 0;
var g_handles_mutex: std.Thread.Mutex = .{};

fn ensureHandles(allocator: std.mem.Allocator, project_id: usize) !void {
    _ = allocator;
    if (project_id >= 256) {
        std.debug.print("[APP_FORWARD] ERROR: project_id {d} >= 256 max projects\\n", .{project_id});
        return;
    }
    if (project_id >= g_handles_len) {
        g_handles_len = project_id + 1;
        // Initialize newly allocated slots
        var i = project_id;
        while (i < g_handles_len) : (i += 1) {
            g_handles_items[i] = .{};
        }
    }
}

fn setHandles(allocator: std.mem.Allocator, project_id: usize, tcp: ?*c.tcp_forwarder_t, udp: ?*c.udp_forwarder_t) !void {
    g_handles_mutex.lock();
    defer g_handles_mutex.unlock();
    try ensureHandles(allocator, project_id);
    std.debug.print("[APP_FORWARD] Registering stats handles for project {d}: tcp={?}, udp={?}\n", .{ project_id, tcp, udp });
    if (tcp == null and udp == null) {
        std.debug.print("[APP_FORWARD] WARNING: Both TCP and UDP handles are null for project {d}!\n", .{project_id});
    }
    g_handles_items[project_id].tcp = tcp;
    g_handles_items[project_id].udp = udp;
}

pub fn getProjectStats(project_id: usize) common.TrafficStats {
    g_handles_mutex.lock();
    defer g_handles_mutex.unlock();
    if (project_id >= g_handles_len) {
        std.debug.print("[APP_FORWARD] getProjectStats({d}): project_id >= g_handles_len={d}\n", .{ project_id, g_handles_len });
        return .{ .bytes_in = 0, .bytes_out = 0 };
    }
    const h = g_handles_items[project_id];
    std.debug.print("[APP_FORWARD] getProjectStats({d}): tcp={?}, udp={?}\n", .{ project_id, h.tcp, h.udp });
    var stats = common.TrafficStats{ .bytes_in = 0, .bytes_out = 0 };
    if (h.tcp) |t| {
        const s = tcp_uv.getStatsRaw(t);
        std.debug.print("[APP_FORWARD]   TCP stats: in={}, out={}\n", .{ s.bytes_in, s.bytes_out });
        stats.bytes_in += s.bytes_in;
        stats.bytes_out += s.bytes_out;
    }
    if (h.udp) |u| {
        const s = udp_uv.getStatsRaw(u);
        std.debug.print("[APP_FORWARD]   UDP stats: in={}, out={}\n", .{ s.bytes_in, s.bytes_out });
        stats.bytes_in += s.bytes_in;
        stats.bytes_out += s.bytes_out;
    }
    std.debug.print("[APP_FORWARD] getProjectStats({d}) final: in={}, out={}\n", .{ project_id, stats.bytes_in, stats.bytes_out });
    return stats;
}

/// 启动一个端口转发项目
pub fn startForwarding(allocator: std.mem.Allocator, project_id: usize, project: types.Project) !void {
    std.debug.print("[APP_FORWARD] startForwarding called for project {d} ({s}), enable_app_forward={}, enable_stats={}\n", .{ project_id, project.remark, project.enable_app_forward, project.enable_stats });
    
    // 总是初始化此项目的 handles 槽位
    try ensureHandles(allocator, project_id);
    
    if (!project.enable_app_forward) {
        std.debug.print("[APP_FORWARD] SKIP: Application-layer forwarding is DISABLED for project {d} - no forwarders created\n", .{project_id});
        return;
    }

    std.debug.print("[APP_FORWARD] Initializing handles for project {d}...\n", .{project_id});
    std.debug.print("[APP_FORWARD] Starting application-layer forwarding for: {s}, enable_stats={}, port_mappings.len={}\n", .{ project.remark, project.enable_stats, project.port_mappings.len });

    // 检查是单端口模式还是多端口模式
    if (project.port_mappings.len > 0) {
        // 多端口模式：为每个映射启动转发
        for (project.port_mappings) |mapping| {
            try startForwardingForMapping(allocator, project, mapping);
        }

        // 主线程等待
        std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60); // 1 year
        return;
    }

    // 单端口模式
    std.debug.print("[APP_FORWARD] Single-port mode: protocol={any}, listen_port={}, target={s}:{}\n", .{ project.protocol, project.listen_port, project.target_address, project.target_port });
    switch (project.protocol) {
        .tcp => {
            std.debug.print("[APP_FORWARD] Creating TCP forwarder for project {d}...\n", .{project_id});
            var tcp_forwarder = try TcpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
                project.enable_stats,
            );
            // Register handle BEFORE starting (uv_run will block)
            try setHandles(allocator, project_id, tcp_forwarder.getHandle(), null);
            server.updateProjectMetrics(project_id, 1, 0, 0);
            std.debug.print("[APP_FORWARD] TCP forwarder handle registered for project {d}, now starting event loop...\n", .{project_id});
            std.debug.print("[APP_FORWARD] Starting TCP forwarder (port {d})...\n", .{project.listen_port});
            try tcp_forwarder.start();
            // This will not return (blocked in uv_run)
            std.debug.print("[APP_FORWARD] TCP forwarder READY for project {d}, active_ports=1, enable_stats={}\n", .{ project_id, project.enable_stats });
            std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60);
        },
        .udp => {
            std.debug.print("[APP_FORWARD] Creating UDP forwarder for project {d}...\n", .{project_id});
            var udp_forwarder = UdpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
                project.enable_stats,
            );
            // Register handle BEFORE starting (uv_run will block)
            try setHandles(allocator, project_id, null, udp_forwarder.getHandle());
            server.updateProjectMetrics(project_id, 1, 0, 0);
            std.debug.print("[APP_FORWARD] UDP forwarder handle registered for project {d}, now starting event loop...\n", .{project_id});
            std.debug.print("[APP_FORWARD] Starting UDP forwarder (port {d})...\n", .{project.listen_port});
            try udp_forwarder.start();
            // This will not return (blocked in uv_run)
            std.debug.print("[APP_FORWARD] UDP forwarder READY for project {d}, active_ports=1, enable_stats={}\n", .{ project_id, project.enable_stats });
            std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60);
        },
        .both => {
            // 同时启动 TCP 和 UDP 转发（单线程持有两端句柄，用于按需统计）
            std.debug.print("[APP_FORWARD] Creating TCP forwarder for project {d}...\n", .{project_id});
            var tcp_forwarder = try TcpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
                project.enable_stats,
            );
            std.debug.print("[APP_FORWARD] Creating UDP forwarder for project {d}...\n", .{project_id});

            var udp_forwarder = UdpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
                project.enable_stats,
            );

            // Register BOTH handles BEFORE starting
            try setHandles(allocator, project_id, tcp_forwarder.getHandle(), udp_forwarder.getHandle());
            server.updateProjectMetrics(project_id, 2, 0, 0);
            std.debug.print("[APP_FORWARD] Both forwarder handles registered for project {d}, now starting event loops...\n", .{project_id});
            
            // Start TCP forwarder (will block in uv_run)
            std.debug.print("[APP_FORWARD] Starting TCP forwarder (port {d})...\n", .{project.listen_port});
            try tcp_forwarder.start();
            // This will not return (blocked in uv_run)
            std.debug.print("[APP_FORWARD] Both TCP+UDP READY for project {d}, active_ports=2, enable_stats={}\n", .{ project_id, project.enable_stats });
            std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60); // 1 year
        },
    }
}

/// 解析端口范围字符串，返回起始和结束端口
fn parsePortRange(port_str: []const u8) !common.PortRange {
    return common.parsePortRange(port_str);
}

/// 为单个端口映射启动转发
fn startForwardingForMapping(
    allocator: std.mem.Allocator,
    project: types.Project,
    mapping: types.PortMapping,
) !void {
    const listen_range = try parsePortRange(mapping.listen_port);
    const target_range = try parsePortRange(mapping.target_port);

    // 验证端口范围长度一致
    const listen_count = listen_range.end - listen_range.start + 1;
    const target_count = target_range.end - target_range.start + 1;

    if (listen_count != target_count) {
        std.debug.print("[Forward] Error: Port range mismatch - listen {d} ports, target {d} ports\n", .{
            listen_count,
            target_count,
        });
        return ForwardError.InvalidAddress;
    }

    // 为范围内的每个端口启动转发
    var i: u16 = 0;
    while (i < listen_count) : (i += 1) {
        const listen_port = listen_range.start + i;
        const target_port = target_range.start + i;

        switch (mapping.protocol) {
            .tcp => {
                const tcp_thread = try std.Thread.spawn(getThreadConfig(), startTcpForward, .{
                    allocator,
                    listen_port,
                    project.target_address,
                    target_port,
                    project.family,
                    project.enable_stats,
                });
                tcp_thread.detach();
            },
            .udp => {
                const udp_thread = try std.Thread.spawn(getThreadConfig(), startUdpForward, .{
                    allocator,
                    listen_port,
                    project.target_address,
                    target_port,
                    project.family,
                    project.enable_stats,
                });
                udp_thread.detach();
            },
            .both => {
                const tcp_thread = try std.Thread.spawn(getThreadConfig(), startTcpForward, .{
                    allocator,
                    listen_port,
                    project.target_address,
                    target_port,
                    project.family,
                    project.enable_stats,
                });
                tcp_thread.detach();

                const udp_thread = try std.Thread.spawn(getThreadConfig(), startUdpForward, .{
                    allocator,
                    listen_port,
                    project.target_address,
                    target_port,
                    project.family,
                    project.enable_stats,
                });
                udp_thread.detach();
            },
        }
    }
}

fn startTcpForward(
    allocator: std.mem.Allocator,
    listen_port: u16,
    target_address: []const u8,
    target_port: u16,
    family: types.AddressFamily,
    enable_stats: bool,
) void {
    var tcp_forwarder = TcpForwarder.init(allocator, listen_port, target_address, target_port, family, enable_stats) catch |err| {
        std.debug.print("[TCP] Failed to create TCP forwarder. Port {d}, target {s}:{d}: {any}\n", .{ listen_port, target_address, target_port, err });
        return;
    };
    tcp_forwarder.start() catch |err| {
        std.debug.print("[TCP] Forward error. Port {d}, forwarding to {s}:{d}: {any}\n", .{ listen_port, target_address, target_port, err });
        return;
    };
    // keep alive
    std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60);
}

fn startUdpForward(
    allocator: std.mem.Allocator,
    listen_port: u16,
    target_address: []const u8,
    target_port: u16,
    family: types.AddressFamily,
    enable_stats: bool,
) void {
    var udp_forwarder = UdpForwarder.init(allocator, listen_port, target_address, target_port, family, enable_stats);
    defer udp_forwarder.deinit();
    udp_forwarder.start() catch |err| {
        std.debug.print("[UDP] Forward error. Port {d}, forwarding to {s}:{d}: {any}\n", .{ listen_port, target_address, target_port, err });
        return;
    };
    std.Thread.sleep(std.time.ns_per_s * 365 * 24 * 60 * 60);
}
