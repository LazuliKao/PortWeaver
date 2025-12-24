const std = @import("std");
const uci = @import("../uci.zig");
const build_options = @import("build_options");
const types = @import("types.zig");
const uci_loader = @import("uci_loader.zig");

const json_loader = if (build_options.enable_json)
    @import("json_loader.zig")
else
    struct {
        pub fn loadFromJsonFile(_: std.mem.Allocator, _: []const u8) !types.Config {
            return types.ConfigError.UnsupportedFeature;
        }
    };

pub const Provider = struct {
    ctx: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        load: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator) anyerror!types.Config,
    };

    pub fn load(self: Provider, allocator: std.mem.Allocator) !types.Config {
        return self.vtable.load(self.ctx, allocator);
    }
};

pub const UciProvider = struct {
    ctx: uci.UciContext,
    package_name: [*c]const u8,

    pub fn asProvider(self: *UciProvider) Provider {
        return .{ .ctx = self, .vtable = &vtable };
    }

    fn loadErased(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!types.Config {
        const self: *UciProvider = @ptrCast(@alignCast(ctx_ptr));
        return uci_loader.loadFromUci(allocator, self.ctx, self.package_name);
    }

    const vtable = Provider.VTable{ .load = loadErased };
};

pub const JsonProvider = if (build_options.enable_json) struct {
    path: []const u8,

    pub fn asProvider(self: *JsonProvider) Provider {
        return .{ .ctx = self, .vtable = &vtable };
    }

    fn loadErased(ctx_ptr: *anyopaque, allocator: std.mem.Allocator) anyerror!types.Config {
        const self: *JsonProvider = @ptrCast(@alignCast(ctx_ptr));
        return json_loader.loadFromJsonFile(allocator, self.path);
    }

    const vtable = Provider.VTable{ .load = loadErased };
} else struct {
    path: []const u8,

    pub fn asProvider(self: *JsonProvider) Provider {
        return .{ .ctx = self, .vtable = &vtable };
    }

    fn loadErased(_: *anyopaque, _: std.mem.Allocator) anyerror!types.Config {
        return types.ConfigError.UnsupportedFeature;
    }

    const vtable = Provider.VTable{ .load = loadErased };
};

pub fn loadFromProvider(allocator: std.mem.Allocator, provider: Provider) !types.Config {
    return provider.load(allocator);
}

test "config: provider abstraction (uci) compiles" {
    // This test only checks the vtable wiring compiles.
    // It does not call into libuci or require OpenWrt runtime.
    const fake_ctx = uci.UciContext{ .ctx = null };
    var p = UciProvider{ .ctx = fake_ctx, .package_name = "portweaver" };
    _ = p.asProvider();
}
