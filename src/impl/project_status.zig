const std = @import("std");
const types = @import("../config/types.zig");
const tcp_uv = @import("app_forward/tcp_forwarder_uv.zig");
const udp_uv = @import("app_forward/udp_forwarder_uv.zig");
pub const TcpForwarder = tcp_uv.TcpForwarder;
pub const UdpForwarder = udp_uv.UdpForwarder;

/// 项目启动状态
pub const StartupStatus = enum(u8) {
    /// 项目未启用（正常）
    disabled = 0,
    /// 启动成功，正在运行
    success = 1,
    /// 启动失败，有错误信息
    failed = 2,

    pub fn toString(self: StartupStatus) [:0]const u8 {
        return switch (self) {
            .disabled => "disabled",
            .success => "success",
            .failed => "failed",
        };
    }
};
pub const ProjectRuntimeInfo = struct {
    active_ports: u32,
    bytes_in: u64,
    bytes_out: u64,
    startup_status: StartupStatus,
    error_code: i32,
};
pub const ProjectHandles = struct {
    startup_status: StartupStatus = .disabled,
    cfg: types.Project,
    error_code: i32 = 0,
    active_ports: u32 = 0,
    id: usize,
    pub fn init(id: usize, cfg: types.Project) ProjectHandles {
        return ProjectHandles{
            .id = id,
            .startup_status = .disabled,
            .cfg = cfg,
            .error_code = 0,
            .active_ports = 0,
        };
    }
    pub fn deinit(self: *ProjectHandles) void {
        // 清理资源（如果有的话）
        _ = self;
    }
    pub inline fn setStartupFailed(self: *ProjectHandles, err_code: i32) void {
        self.startup_status = .failed;
        self.error_code = err_code;
    }
    pub inline fn setStartupSuccess(self: *ProjectHandles) void {
        self.startup_status = .success;
        self.error_code = 0;
    }
    pub inline fn registerTcpHandle(self: *ProjectHandles, _: *TcpForwarder) !void {
        self.active_ports += 1;
    }

    pub inline fn registerUdpHandle(self: *ProjectHandles, _: *UdpForwarder) !void {
        self.active_ports += 1;
    }
};
pub fn stopAll(handles: *std.array_list.Managed(ProjectHandles)) void {
    for (handles.items) |*handle| {
        handle.deinit();
    }
    handles.clearAndFree();
}
