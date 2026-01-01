const std = @import("std");
const types = @import("../config/types.zig");

const common = @import("app_forward/common.zig");
const tcp_uv = @import("app_forward/tcp_forwarder_uv.zig");
const udp_uv = @import("app_forward/udp_forwarder_uv.zig");

pub const ForwardError = common.ForwardError;

pub inline fn getThreadConfig() std.Thread.SpawnConfig {
    return common.getThreadConfig();
}

pub const TcpForwarder = tcp_uv.TcpForwarder;
pub const UdpForwarder = udp_uv.UdpForwarder;

/// 启动一个端口转发项目
pub fn startForwarding(allocator: std.mem.Allocator, project: types.Project) !void {
    if (!project.enable_app_forward) {
        std.debug.print("[Forward] Application-layer forwarding is disabled for this project\n", .{});
        return;
    }

    std.debug.print("[Forward] Starting application-layer forwarding for: {s}\n", .{project.remark});

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
    switch (project.protocol) {
        .tcp => {
            var tcp_forwarder = TcpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
            );
            try tcp_forwarder.start();
        },
        .udp => {
            var udp_forwarder = UdpForwarder.init(
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
            );
            defer udp_forwarder.deinit();
            try udp_forwarder.start();
        },
        .both => {
            // 同时启动 TCP 和 UDP 转发
            const tcp_thread = try std.Thread.spawn(getThreadConfig(), startTcpForward, .{
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
            });
            tcp_thread.detach();

            const udp_thread = try std.Thread.spawn(getThreadConfig(), startUdpForward, .{
                allocator,
                project.listen_port,
                project.target_address,
                project.target_port,
                project.family,
            });
            udp_thread.detach();

            // 主线程等待
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
                });
                tcp_thread.detach();

                const udp_thread = try std.Thread.spawn(getThreadConfig(), startUdpForward, .{
                    allocator,
                    listen_port,
                    project.target_address,
                    target_port,
                    project.family,
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
) void {
    var tcp_forwarder = TcpForwarder.init(allocator, listen_port, target_address, target_port, family);
    tcp_forwarder.start() catch |err| {
        std.debug.print("[TCP] Forward error. Port {d}, forwarding to {s}:{d}: {any}\n", .{ listen_port, target_address, target_port, err });
    };
}

fn startUdpForward(
    allocator: std.mem.Allocator,
    listen_port: u16,
    target_address: []const u8,
    target_port: u16,
    family: types.AddressFamily,
) void {
    var udp_forwarder = UdpForwarder.init(allocator, listen_port, target_address, target_port, family);
    defer udp_forwarder.deinit();
    udp_forwarder.start() catch |err| {
        std.debug.print("[UDP] Forward error. Port {d}, forwarding to {s}:{d}: {any}\n", .{ listen_port, target_address, target_port, err });
    };
}
