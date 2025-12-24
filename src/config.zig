const std = @import("std");
const uci = @import("uci.zig");

pub const ConfigError = error{
	MissingField,
	InvalidValue,
};

pub const AddressFamily = enum {
	any,
	ipv4,
	ipv6,
};

pub const Protocol = enum {
	both,
	tcp,
	udp,
};

/// One port-forwarding project/rule.
///
/// This maps to a UCI section:
///   config project|rule '<name>'
/// and its options.
pub const Project = struct {
	/// 备注
	remark: []const u8 = "",
	/// 地址族限制: IPv4 和 IPv6 / IPv4 / IPv6
	family: AddressFamily = .any,
	/// 协议: TCP+UDP / TCP / UDP
	protocol: Protocol = .both,
	/// 监听端口
	listen_port: u16,
	/// reuseaddr 绑定到本地端口
	reuseaddr: bool = false,
	/// 目标地址
	target_address: []const u8,
	/// 目标端口
	target_port: u16,
	/// 打开防火墙端口
	open_firewall_port: bool = false,
	/// 添加防火墙转发
	add_firewall_forward: bool = false,

	pub fn deinit(self: *Project, allocator: std.mem.Allocator) void {
		if (self.remark.len != 0) allocator.free(self.remark);
		allocator.free(self.target_address);
		self.* = undefined;
	}
};

pub const Config = struct {
	projects: []Project,

	pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
		for (self.projects) |*p| p.deinit(allocator);
		allocator.free(self.projects);
		self.* = undefined;
	}
};

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
	return std.ascii.eqlIgnoreCase(a, b);
}

fn parseBool(val: []const u8) !bool {
	const trimmed = std.mem.trim(u8, val, " \t\r\n");
	if (trimmed.len == 0) return false;

	if (eqlIgnoreCase(trimmed, "1") or eqlIgnoreCase(trimmed, "true") or eqlIgnoreCase(trimmed, "yes") or eqlIgnoreCase(trimmed, "on") or eqlIgnoreCase(trimmed, "enabled")) return true;
	if (eqlIgnoreCase(trimmed, "0") or eqlIgnoreCase(trimmed, "false") or eqlIgnoreCase(trimmed, "no") or eqlIgnoreCase(trimmed, "off") or eqlIgnoreCase(trimmed, "disabled")) return false;

	return ConfigError.InvalidValue;
}

fn parsePort(val: []const u8) !u16 {
	const trimmed = std.mem.trim(u8, val, " \t\r\n");
	const port_u32 = std.fmt.parseUnsigned(u32, trimmed, 10) catch return ConfigError.InvalidValue;
	if (port_u32 == 0 or port_u32 > 65535) return ConfigError.InvalidValue;
	return @intCast(port_u32);
}

fn parseFamily(val: []const u8) !AddressFamily {
	const trimmed = std.mem.trim(u8, val, " \t\r\n");

	if (trimmed.len == 0) return .any;
	if (eqlIgnoreCase(trimmed, "any") or eqlIgnoreCase(trimmed, "all") or eqlIgnoreCase(trimmed, "both") or eqlIgnoreCase(trimmed, "ipv4+ipv6") or eqlIgnoreCase(trimmed, "ipv4_and_ipv6") or eqlIgnoreCase(trimmed, "IPv4 和 IPv6") or eqlIgnoreCase(trimmed, "IPv4和IPv6")) return .any;
	if (eqlIgnoreCase(trimmed, "ipv4") or eqlIgnoreCase(trimmed, "IPv4")) return .ipv4;
	if (eqlIgnoreCase(trimmed, "ipv6") or eqlIgnoreCase(trimmed, "IPv6")) return .ipv6;

	return ConfigError.InvalidValue;
}

fn parseProtocol(val: []const u8) !Protocol {
	const trimmed = std.mem.trim(u8, val, " \t\r\n");

	if (trimmed.len == 0) return .both;
	if (eqlIgnoreCase(trimmed, "both") or eqlIgnoreCase(trimmed, "tcp+udp") or eqlIgnoreCase(trimmed, "TCP+UDP") or eqlIgnoreCase(trimmed, "tcpudp") or eqlIgnoreCase(trimmed, "TCP和UDP") or eqlIgnoreCase(trimmed, "TCP 与 UDP") or eqlIgnoreCase(trimmed, "TCP 和 UDP")) return .both;
	if (eqlIgnoreCase(trimmed, "tcp") or eqlIgnoreCase(trimmed, "TCP")) return .tcp;
	if (eqlIgnoreCase(trimmed, "udp") or eqlIgnoreCase(trimmed, "UDP")) return .udp;

	return ConfigError.InvalidValue;
}

fn dupeIfNonEmpty(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
	if (s.len == 0) return "";
	return allocator.dupe(u8, s);
}

fn parseProjectFromSection(allocator: std.mem.Allocator, sec: uci.UciSection) !Project {
	var project = Project{
		.listen_port = 0,
		.target_address = undefined,
		.target_port = 0,
	};

	var have_listen_port = false;
	var have_target_address = false;
	var have_target_port = false;

	var opt_it = sec.options();
	while (opt_it.next()) |opt| {
		const opt_name = uci.cStr(opt.name());
		if (!opt.isString()) continue;
		const opt_val = uci.cStr(opt.getString());

		if (std.mem.eql(u8, opt_name, "remark") or std.mem.eql(u8, opt_name, "note") or std.mem.eql(u8, opt_name, "备注")) {
			project.remark = try dupeIfNonEmpty(allocator, opt_val);
		} else if (std.mem.eql(u8, opt_name, "family") or std.mem.eql(u8, opt_name, "addr_family") or std.mem.eql(u8, opt_name, "地址族限制")) {
			project.family = try parseFamily(opt_val);
		} else if (std.mem.eql(u8, opt_name, "protocol") or std.mem.eql(u8, opt_name, "proto") or std.mem.eql(u8, opt_name, "协议")) {
			project.protocol = try parseProtocol(opt_val);
		} else if (std.mem.eql(u8, opt_name, "listen_port") or std.mem.eql(u8, opt_name, "src_port") or std.mem.eql(u8, opt_name, "监听端口")) {
			project.listen_port = try parsePort(opt_val);
			have_listen_port = true;
		} else if (std.mem.eql(u8, opt_name, "reuseaddr") or std.mem.eql(u8, opt_name, "reuse") or std.mem.eql(u8, opt_name, "reuse_addr") or std.mem.eql(u8, opt_name, "绑定到本地端口")) {
			project.reuseaddr = try parseBool(opt_val);
		} else if (std.mem.eql(u8, opt_name, "target_address") or std.mem.eql(u8, opt_name, "target_addr") or std.mem.eql(u8, opt_name, "dst_ip") or std.mem.eql(u8, opt_name, "目标地址")) {
			const trimmed = std.mem.trim(u8, opt_val, " \t\r\n");
			if (trimmed.len == 0) return ConfigError.InvalidValue;
			project.target_address = try allocator.dupe(u8, trimmed);
			have_target_address = true;
		} else if (std.mem.eql(u8, opt_name, "target_port") or std.mem.eql(u8, opt_name, "dst_port") or std.mem.eql(u8, opt_name, "目标端口")) {
			project.target_port = try parsePort(opt_val);
			have_target_port = true;
		} else if (std.mem.eql(u8, opt_name, "open_firewall_port") or std.mem.eql(u8, opt_name, "firewall_open") or std.mem.eql(u8, opt_name, "打开防火墙端口")) {
			project.open_firewall_port = try parseBool(opt_val);
		} else if (std.mem.eql(u8, opt_name, "add_firewall_forward") or std.mem.eql(u8, opt_name, "firewall_forward") or std.mem.eql(u8, opt_name, "添加防火墙转发")) {
			project.add_firewall_forward = try parseBool(opt_val);
		}
	}

	if (!have_listen_port or !have_target_address or !have_target_port) {
		if (have_target_address) allocator.free(project.target_address);
		if (project.remark.len != 0) allocator.free(project.remark);
		return ConfigError.MissingField;
	}

	return project;
}

/// Load projects from a UCI config package (e.g. `/etc/config/portweaver`).
///
/// Expected schema (one section per project):
///   config project 'name'
///     option remark '...'
///     option family 'any|ipv4|ipv6'
///     option protocol 'both|tcp|udp'
///     option listen_port '3389'
///     option reuseaddr '1'
///     option target_address '192.168.1.2'
///     option target_port '3389'
///     option open_firewall_port '1'
///     option add_firewall_forward '1'
pub fn loadFromUci(allocator: std.mem.Allocator, ctx: uci.UciContext, package_name: [*c]const u8) !Config {
	var pkg = try ctx.load(package_name);
	if (pkg.isNull()) return ConfigError.MissingField;
	defer pkg.unload() catch {};

	var list = std.ArrayList(Project).init(allocator);
	errdefer {
		for (list.items) |*p| p.deinit(allocator);
		list.deinit();
	}

	var sec_it = uci.sections(pkg);
	while (sec_it.next()) |sec| {
		const sec_type = uci.cStr(sec.sectionType());
		if (!(std.mem.eql(u8, sec_type, "project") or std.mem.eql(u8, sec_type, "rule"))) continue;

		const project = try parseProjectFromSection(allocator, sec);
		try list.append(project);
	}

	return .{ .projects = try list.toOwnedSlice() };
}

test "config: parse bool" {
	try std.testing.expect(try parseBool("1"));
	try std.testing.expect(try parseBool("true"));
	try std.testing.expect(!(try parseBool("0")));
	try std.testing.expect(!(try parseBool("false")));
}

test "config: parse enums" {
	try std.testing.expectEqual(AddressFamily.any, try parseFamily("IPv4 和 IPv6"));
	try std.testing.expectEqual(AddressFamily.ipv4, try parseFamily("ipv4"));
	try std.testing.expectEqual(Protocol.both, try parseProtocol("TCP+UDP"));
	try std.testing.expectEqual(Protocol.tcp, try parseProtocol("tcp"));
}
