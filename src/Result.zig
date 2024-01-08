const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Rows = @import("Rows.zig");
const oid = @import("./oid.zig");

pub const PGResult = c.PGresult;
pub const PGConnection = c.PGconn;

pub const Result = @This();

/// DO NOT USE THIS POINTER
pq_res: *PGResult,

pub const Ping = enum(u8) {
    ok,
    reject,
    no_response,
    no_attempt,
};

pub const Status = enum {
    tuples_ok,
    command_ok,
    polling_ok,
    copy_in,
    copy_out,
    copy_both,
    empty_query,
    fatal_error,
    bad_response,
    simgle_tuple,
    pipeline_sync,
    polling_active,
    nonfatal_error,
};

/// TODO: implove it
pub const Error = error{
    QueryFailed,
};

pub fn rows(result: *Result, allocator: std.mem.Allocator) Rows {
    return .{
        .res = result,
        .arena = std.heap.ArenaAllocator.init(allocator),
        .max_col_number = result.nCols(),
        .max_row_number = result.nRows(),
    };
}

/// this function is a FOOTGUN
fn init() Result {
    return .{ .pq_res = undefined };
}

pub fn deinit(res: *Result) void {
    c.PQclear(res.pq_res);
}

pub fn nRows(res: *Result) usize {
    return @intCast(c.PQntuples(res.pq_res));
}

pub fn nCols(result: *const Result) usize {
    return @intCast(c.PQnfields(result.pq_res));
}

pub fn nParams(result: *const Result) usize {
    return @intCast(c.PQnparams(result.pq_res));
}

pub fn user(result: *const Result) ?[]const u8 {
    const user_str = std.mem.span(c.PQuser(result.pq_res));
    return if (user_str.len == 0) null else user_str;
}

pub fn port(result: *const Result) ?[]const u8 {
    const port_str = std.mem.span(c.PQport(result.pq_res));
    if (port_str.len == 0) null else port_str;
}

pub fn ping(result: *const Result) Ping {
    return @enumFromInt(c.PQping(result.pq_res));
}

pub fn host(result: *const Result) ?[]const u8 {
    const host_str = std.mem.span(c.PQhost(result.pq_res));
    return if (host_str.len == 0) null else host_str;
}

pub fn db(result: *const Result) ?[]const u8 {
    const db_str = std.mem.span(c.PQdb(result.pq_res));
    return if (db_str.len == 0) null else db_str;
}

pub fn pass(result: *const Result) usize {
    return std.mem.span(c.PQpass(result.pq_res));
}

pub fn reset(result: *const Result) void {
    c.PQreset(result.pq_res);
}

pub fn colName(result: *const Result, col_number: usize) []const u8 {
    const c_col_number: c_int = @intCast(col_number);
    return std.mem.span(c.PQfname(result.pq_res, c_col_number));
}

/// BUG: Why is col_name.ptr SO CRAZY???
pub fn colNumber(result: *const Result, col_name: []const u8) ?usize {
    const col = c.PQfnumber(result.pq_res, col_name.ptr);
    return if (col == -1) null else @intCast(col);
}

pub fn colType(result: *const Result, col_number: usize) oid.Oid {
    const c_col_number: c_int = @intCast(col_number);
    const i = c.PQftype(result.pq_res, c_col_number);
    return @enumFromInt(i);
}

pub fn colTypeName(result: *const Result, col_number: usize) []const u8 {
    const c_col_number: c_int = @intCast(col_number);
    return @intCast(c.PQftypeName(result.pq_res, c_col_number));
}

pub fn printResult(result: *const Result) void {
    const n_col = result.nCols();
    const n_row = result.nRows();

    for (0..n_row) |i| {
        for (0..n_col) |j| {
            const c_i: c_int = @intCast(i);
            const c_j: c_int = @intCast(j);
            std.debug.print("{s} ", .{c.PQgetvalue(result.pq_res, c_i, c_j)});
        }
        std.debug.print("\n", .{});
    }
}

pub fn getValue(result: *Result, row_number: usize, col_number: usize) ?[]const u8 {
    const c_row_number: c_int = @intCast(row_number);
    const c_col_number: c_int = @intCast(col_number);
    const string_value = std.mem.span(c.PQgetvalue(result.pq_res, c_row_number, c_col_number));
    return if (string_value.len == 0) null else string_value;
}

/// return an error if not ok
pub fn checkStatus(result: *Result) !void {
    return switch (c.PQresultStatus(result.pq_res)) {
        c.PGRES_TUPLES_OK,
        c.PGRES_COMMAND_OK,
        c.PGRES_POLLING_OK,
        => {},
        else => |s| b: {
            std.log.err("result status: {}\n", .{s});
            break :b error.CommandFailed;
        },
    };
}

pub fn status(res: *Result) Status {
    return switch (c.PQresultStatus(res.pg_res)) {
        c.PGRES_TUPLES_OK => .tuples_ok,
        c.PGRES_COMMAND_OK => .command_ok,
        c.PGRES_POLLING_OK => .polling_ok,
        c.PGRES_COPY_IN => .copy_in,
        c.PGRES_COPY_OUT => .copy_out,
        c.PGRES_COPY_BOTH => .copy_both,
        c.PGRES_EMPTY_QUERY => .empty_query,
        c.PGRES_FATAL_ERROR => .fatal_error,
        c.PGRES_BAD_RESPONSE => .bad_response,
        c.PGRES_SINGLE_TUPLE => .simgle_tuple,
        c.PGRES_PIPELINE_SYNC => .pipeline_sync,
        c.PGRES_POLLING_ACTIVE => .polling_active,
        c.PGRES_NONFATAL_ERROR => .nonfatal_error,
        else => unreachable,
    };
}
