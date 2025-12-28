const std = @import("std");
const types = @import("types.zig");

fn jsonGetAliased(obj: std.json.ObjectMap, keys: []const []const u8) ?std.json.Value {
    for (keys) |k| {
        if (obj.get(k)) |v| return v;
    }
    return null;
}

fn parseJsonBool(v: std.json.Value) !bool {
    return switch (v) {
        .bool => |b| b,
        .integer => |i| i != 0,
        .string => |s| try types.parseBool(s),
        else => types.ConfigError.InvalidValue,
    };
}

fn parseJsonPort(v: std.json.Value) !u16 {
    return switch (v) {
        .integer => |i| {
            if (i <= 0 or i > 65535) return types.ConfigError.InvalidValue;
            return @intCast(i);
        },
        .string => |s| try types.parsePort(s),
        else => types.ConfigError.InvalidValue,
    };
}

fn parseJsonString(v: std.json.Value) ![]const u8 {
    return switch (v) {
        .string => |s| s,
        else => types.ConfigError.InvalidValue,
    };
}

fn appendZoneString(list: *std.array_list.Managed([]const u8), allocator: std.mem.Allocator, s: []const u8) !void {
    const trimmed = std.mem.trim(u8, s, " \t\r\n");
    if (trimmed.len == 0) return;
    try list.append(try allocator.dupe(u8, trimmed));
}

fn parseJsonZones(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    out: *std.array_list.Managed([]const u8),
) !void {
    switch (v) {
        .string => |s| try appendZoneString(out, allocator, s),
        .array => |a| {
            for (a.items) |item| {
                const s = try parseJsonString(item);
                try appendZoneString(out, allocator, s);
            }
        },
        else => return types.ConfigError.InvalidValue,
    }
}

pub fn loadFromJsonFile(allocator: std.mem.Allocator, path: []const u8) !types.Config {
    const json_text = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch return types.ConfigError.JsonParseError;
    defer allocator.free(json_text);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_text, .{}) catch return types.ConfigError.JsonParseError;
    defer parsed.deinit();

    var list = std.array_list.Managed(types.Project).init(allocator);
    errdefer {
        for (list.items) |*p| p.deinit(allocator);
        list.deinit();
    }

    const root = parsed.value;
    const projects_value: std.json.Value = switch (root) {
        .array => root,
        .object => |o| jsonGetAliased(o, &.{ "projects", "items", "rules" }) orelse return types.ConfigError.MissingField,
        else => return types.ConfigError.InvalidValue,
    };

    if (projects_value != .array) return types.ConfigError.InvalidValue;

    for (projects_value.array.items) |item| {
        if (item != .object) return types.ConfigError.InvalidValue;
        const obj = item.object;

        var project = types.Project{
            .listen_port = 0,
            .target_address = undefined,
            .target_port = 0,
        };

        var have_listen_port = false;
        var have_target_address = false;
        var have_target_port = false;

        var src_zones_list = std.array_list.Managed([]const u8).init(allocator);
        defer src_zones_list.deinit();
        errdefer {
            for (src_zones_list.items) |z| allocator.free(z);
        }

        var dest_zones_list = std.array_list.Managed([]const u8).init(allocator);
        defer dest_zones_list.deinit();
        errdefer {
            for (dest_zones_list.items) |z| allocator.free(z);
        }

        if (jsonGetAliased(obj, &.{ "remark", "note", "备注" })) |v| {
            const s = try parseJsonString(v);
            project.remark = try types.dupeIfNonEmpty(allocator, s);
        }

        if (jsonGetAliased(obj, &.{ "src_zone", "source_zone", "srcZone", "src-zone", "来源区域", "源区域" })) |v| {
            try parseJsonZones(allocator, v, &src_zones_list);
        }

        if (jsonGetAliased(obj, &.{ "dest_zone", "destination_zone", "dst_zone", "destZone", "dest-zone", "目标区域" })) |v| {
            try parseJsonZones(allocator, v, &dest_zones_list);
        }

        if (jsonGetAliased(obj, &.{ "family", "addr_family", "地址族限制" })) |v| {
            const s = try parseJsonString(v);
            project.family = try types.parseFamily(s);
        }

        if (jsonGetAliased(obj, &.{ "protocol", "proto", "协议" })) |v| {
            const s = try parseJsonString(v);
            project.protocol = try types.parseProtocol(s);
        }

        if (jsonGetAliased(obj, &.{ "listen_port", "src_port", "监听端口" })) |v| {
            project.listen_port = try parseJsonPort(v);
            have_listen_port = true;
        }

        if (jsonGetAliased(obj, &.{ "reuseaddr", "reuse", "reuse_addr", "绑定到本地端口" })) |v| {
            project.reuseaddr = try parseJsonBool(v);
        }

        if (jsonGetAliased(obj, &.{ "target_address", "target_addr", "dst_ip", "目标地址" })) |v| {
            const s = try parseJsonString(v);
            const trimmed = std.mem.trim(u8, s, " \t\r\n");
            if (trimmed.len == 0) return types.ConfigError.InvalidValue;
            project.target_address = try allocator.dupe(u8, trimmed);
            have_target_address = true;
        }

        if (jsonGetAliased(obj, &.{ "target_port", "dst_port", "目标端口" })) |v| {
            project.target_port = try parseJsonPort(v);
            have_target_port = true;
        }

        if (jsonGetAliased(obj, &.{ "open_firewall_port", "firewall_open", "打开防火墙端口" })) |v| {
            project.open_firewall_port = try parseJsonBool(v);
        }

        if (jsonGetAliased(obj, &.{ "add_firewall_forward", "firewall_forward", "添加防火墙转发" })) |v| {
            project.add_firewall_forward = try parseJsonBool(v);
        }

        if (!have_listen_port or !have_target_address or !have_target_port) {
            if (have_target_address) allocator.free(project.target_address);
            if (project.remark.len != 0) allocator.free(project.remark);
            return types.ConfigError.MissingField;
        }

        if (src_zones_list.items.len != 0) {
            project.src_zones = try src_zones_list.toOwnedSlice();
        }
        if (dest_zones_list.items.len != 0) {
            project.dest_zones = try dest_zones_list.toOwnedSlice();
        }

        try list.append(project);
    }

    return .{ .projects = try list.toOwnedSlice() };
}
