const std = @import("std");
const DynamicLibLoader = @import("../loader/dynamic_lib.zig").DynamicLibLoader;

pub const c = @cImport({
    @cInclude("posix_missing_fix.h");
    @cInclude("libubox/blobmsg_json.h");
    @cInclude("libubox/uloop.h");
    @cInclude("libubus.h");
});

const blob_buf_init_fn = *const fn (*c.blob_buf, c_int) callconv(.c) c_int;
const blob_buf_free_fn = *const fn (*c.blob_buf) callconv(.c) void;
const blobmsg_add_field_fn = *const fn (*c.blob_buf, c_int, [*c]const u8, ?*const anyopaque, c_uint) callconv(.c) c_int;
const blobmsg_open_nested_fn = *const fn (*c.blob_buf, [*c]const u8, c.bool) callconv(.c) ?*anyopaque;
const blob_nest_end_fn = *const fn (*c.blob_buf, ?*anyopaque) callconv(.c) void;
const blobmsg_parse_fn = *const fn ([*c]const c.blobmsg_policy, c_int, [*c]?*c.blob_attr, ?*anyopaque, c_uint) callconv(.c) c_int;

const uloop_init_fn = *const fn () callconv(.c) c_int;
const uloop_run_timeout_fn = *const fn (c_int) callconv(.c) c_int;
const uloop_done_fn = *const fn () callconv(.c) void;
const uloop_fd_add_fn = *const fn (*c.uloop_fd, c_uint) callconv(.c) c_int;

var lib_loader = DynamicLibLoader.init();
var fn_blob_buf_init: ?blob_buf_init_fn = null;
var fn_blob_buf_free: ?blob_buf_free_fn = null;
var fn_blobmsg_add_field: ?blobmsg_add_field_fn = null;
var fn_blobmsg_open_nested: ?blobmsg_open_nested_fn = null;
var fn_blob_nest_end: ?blob_nest_end_fn = null;
var fn_blobmsg_parse: ?blobmsg_parse_fn = null;
var fn_uloop_init: ?uloop_init_fn = null;
var fn_uloop_run_timeout: ?uloop_run_timeout_fn = null;
var fn_uloop_done: ?uloop_done_fn = null;
var fn_uloop_fd_add: ?uloop_fd_add_fn = null;

fn ensureLibLoaded() !void {
    if (lib_loader.isLoaded()) return;
    try lib_loader.load("libubox");
}

fn loadFunction(comptime T: type, comptime name: [:0]const u8, cache: *?T) !T {
    if (cache.*) |func| return func;
    try ensureLibLoaded();
    const func = try lib_loader.lookup(T, name);
    cache.* = func;
    return func;
}

pub fn blobBufInit(buf: *c.blob_buf, id: c_int) !void {
    const func = try loadFunction(blob_buf_init_fn, "blob_buf_init", &fn_blob_buf_init);
    if (func(buf, id) != 0) return error.BlobBufInitFailed;
}

pub fn blobBufFree(buf: *c.blob_buf) !void {
    const func = try loadFunction(blob_buf_free_fn, "blob_buf_free", &fn_blob_buf_free);
    func(buf);
}

pub fn blobmsgAddField(buf: *c.blob_buf, field_type: c_int, name: [:0]const u8, data: ?*const anyopaque, len: usize) !void {
    const func = try loadFunction(blobmsg_add_field_fn, "blobmsg_add_field", &fn_blobmsg_add_field);
    _ = func(buf, field_type, name.ptr, data, @intCast(len));
}

pub fn blobmsgOpenNested(buf: *c.blob_buf, name: ?[:0]const u8, is_array: bool) !?*anyopaque {
    const func = try loadFunction(blobmsg_open_nested_fn, "blobmsg_open_nested", &fn_blobmsg_open_nested);
    const ptr: [*c]const u8 = if (name) |n| n.ptr else @ptrFromInt(0);
    return func(buf, ptr, is_array);
}

pub fn blobNestEnd(buf: *c.blob_buf, cookie: ?*anyopaque) !void {
    const func = try loadFunction(blob_nest_end_fn, "blob_nest_end", &fn_blob_nest_end);
    func(buf, cookie);
}

pub fn blobmsgParse(policy: []const c.blobmsg_policy, table: []?*c.blob_attr, data: ?*anyopaque, data_len: usize) !void {
    const func = try loadFunction(blobmsg_parse_fn, "blobmsg_parse", &fn_blobmsg_parse);
    const rc = func(policy.ptr, @intCast(policy.len), table.ptr, data, @intCast(data_len));
    if (rc < 0) return error.BlobParseFailed;
}

pub fn uloopInit() !void {
    const func = try loadFunction(uloop_init_fn, "uloop_init", &fn_uloop_init);
    if (func() != 0) return error.UloopInitFailed;
}

pub fn uloopRun(timeout_ms: c_int) !void {
    const func = try loadFunction(uloop_run_timeout_fn, "uloop_run_timeout", &fn_uloop_run_timeout);
    _ = func(timeout_ms);
}

pub fn uloopDone() !void {
    const func = try loadFunction(uloop_done_fn, "uloop_done", &fn_uloop_done);
    func();
}

pub fn uloopFdAdd(fd: *c.uloop_fd, flags: c_uint) !void {
    const func = try loadFunction(uloop_fd_add_fn, "uloop_fd_add", &fn_uloop_fd_add);
    if (func(fd, flags) != 0) return error.UloopAddFdFailed;
}
