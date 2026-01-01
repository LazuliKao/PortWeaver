const std = @import("std");
const builtin = @import("builtin");
const DynamicLibLoader = @import("../loader/dynamic_lib.zig").DynamicLibLoader;

const c = @cImport({
    @cInclude("posix_missing_fix.h");
    @cInclude("unistd.h");
    @cInclude("signal.h");
    @cInclude("libubox/blobmsg_json.h");
    @cInclude("libubus.h");
});
// 定义函数类型
const ubus_connect_fn = *const fn (path: [*c]const u8) callconv(.c) ?*c.ubus_context;
const ubus_connect_ctx_fn = *const fn (ctx: *c.ubus_context, path: [*c]const u8) callconv(.c) c_int;
const ubus_free_fn = *const fn (ctx: *c.ubus_context) callconv(.c) void;
const ubus_shutdown_fn = *const fn (ctx: *c.ubus_context) callconv(.c) void;
const ubus_reconnect_fn = *const fn (ctx: *c.ubus_context, path: [*c]const u8) callconv(.c) c_int;
const ubus_lookup_id_fn = *const fn (ctx: *c.ubus_context, path: [*c]const u8, id: *u32) callconv(.c) c_int;
const ubus_add_object_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_object) callconv(.c) c_int;
const ubus_remove_object_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_object) callconv(.c) c_int;
const ubus_register_subscriber_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_subscriber) callconv(.c) c_int;
const ubus_subscribe_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_subscriber, id: u32) callconv(.c) c_int;
const ubus_unsubscribe_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_subscriber, id: u32) callconv(.c) c_int;
const ubus_invoke_fd_fn = *const fn (ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, cb: ?c.ubus_data_handler_t, priv: ?*anyopaque, timeout: c_int, fd: c_int) callconv(.c) c_int;
const ubus_invoke_async_fd_fn = *const fn (ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, req: *c.ubus_request, fd: c_int) callconv(.c) c_int;
const ubus_send_reply_fn = *const fn (ctx: *c.ubus_context, req: *c.ubus_request_data, msg: [*c]c.blob_attr) callconv(.c) c_int;
const ubus_complete_deferred_request_fn = *const fn (ctx: *c.ubus_context, req: *c.ubus_request_data, ret: c_int) callconv(.c) void;
const ubus_notify_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_object, type_name: [*c]const u8, msg: [*c]c.blob_attr, timeout: c_int) callconv(.c) c_int;
const ubus_notify_async_fn = *const fn (ctx: *c.ubus_context, obj: *c.ubus_object, type_name: [*c]const u8, msg: [*c]c.blob_attr, req: *c.ubus_notify_request) callconv(.c) c_int;
const ubus_send_event_fn = *const fn (ctx: *c.ubus_context, id: [*c]const u8, data: [*c]c.blob_attr) callconv(.c) c_int;
const ubus_register_event_handler_fn = *const fn (ctx: *c.ubus_context, ev: *c.ubus_event_handler, pattern: [*c]const u8) callconv(.c) c_int;
const ubus_complete_request_fn = *const fn (ctx: *c.ubus_context, req: *c.ubus_request, timeout: c_int) callconv(.c) c_int;
const ubus_complete_request_async_fn = *const fn (ctx: *c.ubus_context, req: *c.ubus_request) callconv(.c) void;
const ubus_abort_request_fn = *const fn (ctx: *c.ubus_context, req: *c.ubus_request) callconv(.c) void;
const ubus_lookup_fn = *const fn (ctx: *c.ubus_context, path: [*c]const u8, cb: ?c.ubus_lookup_handler_t, priv: ?*anyopaque) callconv(.c) c_int;
const ubus_strerror_fn = *const fn (error_code: c_int) callconv(.c) [*c]const u8;

// 全局变量
var fn_connect: ?ubus_connect_fn = null;
var fn_connect_ctx: ?ubus_connect_ctx_fn = null;
var fn_free: ?ubus_free_fn = null;
var fn_shutdown: ?ubus_shutdown_fn = null;
var fn_reconnect: ?ubus_reconnect_fn = null;
var fn_lookup_id: ?ubus_lookup_id_fn = null;
var fn_add_object: ?ubus_add_object_fn = null;
var fn_remove_object: ?ubus_remove_object_fn = null;
var fn_register_subscriber: ?ubus_register_subscriber_fn = null;
var fn_subscribe: ?ubus_subscribe_fn = null;
var fn_unsubscribe: ?ubus_unsubscribe_fn = null;
var fn_invoke_fd: ?ubus_invoke_fd_fn = null;
var fn_invoke_async_fd: ?ubus_invoke_async_fd_fn = null;
var fn_send_reply: ?ubus_send_reply_fn = null;
var fn_complete_deferred_request: ?ubus_complete_deferred_request_fn = null;
var fn_notify: ?ubus_notify_fn = null;
var fn_notify_async: ?ubus_notify_async_fn = null;
var fn_send_event: ?ubus_send_event_fn = null;
var fn_register_event_handler: ?ubus_register_event_handler_fn = null;
var fn_complete_request: ?ubus_complete_request_fn = null;
var fn_complete_request_async: ?ubus_complete_request_async_fn = null;
var fn_abort_request: ?ubus_abort_request_fn = null;
var fn_lookup: ?ubus_lookup_fn = null;
var fn_strerror: ?ubus_strerror_fn = null;

var lib_loader = DynamicLibLoader.init();

fn ensureLibLoaded() !void {
    if (lib_loader.isLoaded()) return;
    try lib_loader.load("libubus");
}

fn loadFunction(comptime T: type, comptime name: [:0]const u8, cache: *?T) !T {
    if (cache.*) |func| {
        return func;
    }

    try ensureLibLoaded();

    const func = try lib_loader.lookup(T, name);
    cache.* = func;
    return func;
}

// 包装函数
pub inline fn ubus_connect(path: [*c]const u8) !?*c.ubus_context {
    const func = try loadFunction(ubus_connect_fn, "ubus_connect", &fn_connect);
    return func(path);
}

pub inline fn ubus_connect_ctx(ctx: *c.ubus_context, path: [*c]const u8) !c_int {
    const func = try loadFunction(ubus_connect_ctx_fn, "ubus_connect_ctx", &fn_connect_ctx);
    return func(ctx, path);
}

pub inline fn ubus_free(ctx: *c.ubus_context) !void {
    const func = try loadFunction(ubus_free_fn, "ubus_free", &fn_free);
    func(ctx);
}

pub inline fn ubus_shutdown(ctx: *c.ubus_context) !void {
    const func = try loadFunction(ubus_shutdown_fn, "ubus_shutdown", &fn_shutdown);
    func(ctx);
}

pub inline fn ubus_reconnect(ctx: *c.ubus_context, path: [*c]const u8) !c_int {
    const func = try loadFunction(ubus_reconnect_fn, "ubus_reconnect", &fn_reconnect);
    return func(ctx, path);
}

pub inline fn ubus_lookup_id(ctx: *c.ubus_context, path: [*c]const u8, id: *u32) !c_int {
    const func = try loadFunction(ubus_lookup_id_fn, "ubus_lookup_id", &fn_lookup_id);
    return func(ctx, path, id);
}

pub inline fn ubus_add_object(ctx: *c.ubus_context, obj: *c.ubus_object) !c_int {
    const func = try loadFunction(ubus_add_object_fn, "ubus_add_object", &fn_add_object);
    return func(ctx, obj);
}

pub inline fn ubus_remove_object(ctx: *c.ubus_context, obj: *c.ubus_object) !c_int {
    const func = try loadFunction(ubus_remove_object_fn, "ubus_remove_object", &fn_remove_object);
    return func(ctx, obj);
}

pub inline fn ubus_register_subscriber(ctx: *c.ubus_context, obj: *c.ubus_subscriber) !c_int {
    const func = try loadFunction(ubus_register_subscriber_fn, "ubus_register_subscriber", &fn_register_subscriber);
    return func(ctx, obj);
}

pub inline fn ubus_subscribe(ctx: *c.ubus_context, obj: *c.ubus_subscriber, id: u32) !c_int {
    const func = try loadFunction(ubus_subscribe_fn, "ubus_subscribe", &fn_subscribe);
    return func(ctx, obj, id);
}

pub inline fn ubus_unsubscribe(ctx: *c.ubus_context, obj: *c.ubus_subscriber, id: u32) !c_int {
    const func = try loadFunction(ubus_unsubscribe_fn, "ubus_unsubscribe", &fn_unsubscribe);
    return func(ctx, obj, id);
}

pub inline fn ubus_invoke_fd(ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, cb: ?c.ubus_data_handler_t, priv: ?*anyopaque, timeout: c_int, fd: c_int) !c_int {
    const func = try loadFunction(ubus_invoke_fd_fn, "ubus_invoke_fd", &fn_invoke_fd);
    return func(ctx, obj, method, msg, cb, priv, timeout, fd);
}

pub inline fn ubus_invoke(ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, cb: ?c.ubus_data_handler_t, priv: ?*anyopaque, timeout: c_int) !c_int {
    return try ubus_invoke_fd(ctx, obj, method, msg, cb, priv, timeout, -1);
}

pub inline fn ubus_invoke_async_fd(ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, req: *c.ubus_request, fd: c_int) !c_int {
    const func = try loadFunction(ubus_invoke_async_fd_fn, "ubus_invoke_async_fd", &fn_invoke_async_fd);
    return func(ctx, obj, method, msg, req, fd);
}

pub inline fn ubus_invoke_async(ctx: *c.ubus_context, obj: u32, method: [*c]const u8, msg: [*c]c.blob_attr, req: *c.ubus_request) !c_int {
    return try ubus_invoke_async_fd(ctx, obj, method, msg, req, -1);
}

pub inline fn ubus_send_reply(ctx: *c.ubus_context, req: *c.ubus_request_data, msg: [*c]c.blob_attr) !c_int {
    const func = try loadFunction(ubus_send_reply_fn, "ubus_send_reply", &fn_send_reply);
    return func(ctx, req, msg);
}

pub inline fn ubus_complete_deferred_request(ctx: *c.ubus_context, req: *c.ubus_request_data, ret: c_int) !void {
    const func = try loadFunction(ubus_complete_deferred_request_fn, "ubus_complete_deferred_request", &fn_complete_deferred_request);
    func(ctx, req, ret);
}

pub inline fn ubus_notify(ctx: *c.ubus_context, obj: *c.ubus_object, type_name: [*c]const u8, msg: [*c]c.blob_attr, timeout: c_int) !c_int {
    const func = try loadFunction(ubus_notify_fn, "ubus_notify", &fn_notify);
    return func(ctx, obj, type_name, msg, timeout);
}

pub inline fn ubus_notify_async(ctx: *c.ubus_context, obj: *c.ubus_object, type_name: [*c]const u8, msg: [*c]c.blob_attr, req: *c.ubus_notify_request) !c_int {
    const func = try loadFunction(ubus_notify_async_fn, "ubus_notify_async", &fn_notify_async);
    return func(ctx, obj, type_name, msg, req);
}

pub inline fn ubus_send_event(ctx: *c.ubus_context, id: [*c]const u8, data: [*c]c.blob_attr) !c_int {
    const func = try loadFunction(ubus_send_event_fn, "ubus_send_event", &fn_send_event);
    return func(ctx, id, data);
}

pub inline fn ubus_register_event_handler(ctx: *c.ubus_context, ev: *c.ubus_event_handler, pattern: [*c]const u8) !c_int {
    const func = try loadFunction(ubus_register_event_handler_fn, "ubus_register_event_handler", &fn_register_event_handler);
    return func(ctx, ev, pattern);
}

pub inline fn ubus_complete_request(ctx: *c.ubus_context, req: *c.ubus_request, timeout: c_int) !c_int {
    const func = try loadFunction(ubus_complete_request_fn, "ubus_complete_request", &fn_complete_request);
    return func(ctx, req, timeout);
}

pub inline fn ubus_complete_request_async(ctx: *c.ubus_context, req: *c.ubus_request) !void {
    const func = try loadFunction(ubus_complete_request_async_fn, "ubus_complete_request_async", &fn_complete_request_async);
    func(ctx, req);
}

pub inline fn ubus_abort_request(ctx: *c.ubus_context, req: *c.ubus_request) !void {
    const func = try loadFunction(ubus_abort_request_fn, "ubus_abort_request", &fn_abort_request);
    func(ctx, req);
}

pub inline fn ubus_lookup(ctx: *c.ubus_context, path: [*c]const u8, cb: ?c.ubus_lookup_handler_t, priv: ?*anyopaque) !c_int {
    const func = try loadFunction(ubus_lookup_fn, "ubus_lookup", &fn_lookup);
    return func(ctx, path, cb, priv);
}

pub inline fn ubus_strerror(error_code: c_int) ![*c]const u8 {
    const func = try loadFunction(ubus_strerror_fn, "ubus_strerror", &fn_strerror);
    return func(error_code);
}

pub inline fn isLoaded() bool {
    return lib_loader.isLoaded();
}
