const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Rows = @import("Rows.zig");
const Result = @import("Result.zig");

pub const PGResult = c.PGresult;
pub const PGConnection = c.PGconn;

pub const Connection = @This();
/// DO NOT USE THIS POINTER
pq_conn: *c.PGconn,
allocator: std.mem.Allocator,

pub const Error = error{
    ConnectionFailed,
    SomeError,
    BadConnection,
};

pub const Status = enum {
    /// connection is ready.
    ok,
    /// connection procedure has failed.
    bad,
    /// waiting for connection to be made.
    started,
    /// connection ok; waiting to send.
    made,
    /// waiting for a response from the server.
    awaiting_response,
    /// received authentication; waiting for backend start-up to finish.
    auth_ok,
    /// negotiating ssl encryption.
    ssl_startup,
    /// negotiating environment-driven parameter settings.
    setenv,
    /// checking if connection is able to handle write transactions.
    check_writable,
    /// consuming any remaining response messages on connection.
    consume,
    /// No idea
    needed,
};

/// Init the connection. Error may occur if the connection can not be established
pub fn init(allocator: std.mem.Allocator, conn_info: []const u8) Error!Connection {
    const pq_conn = c.PQconnectdb(conn_info.ptr) orelse return error.BadConnection;
    errdefer c.PQfinish(pq_conn);

    if (c.PQstatus(pq_conn) != c.CONNECTION_OK) {
        std.log.err("Connection Error: {s}", .{c.PQerrorMessage(pq_conn)});
        return error.ConnectionFailed;
    }

    return .{
        .allocator = allocator,
        .pq_conn = pq_conn,
    };
}

pub fn begin(conn: *Connection) !void {
    try conn.run("BEGIN", .{});
}

pub fn end(conn: *Connection) !void {
    try conn.run("END", .{});
}

pub fn rollBack(conn: *Connection) !void {
    try conn.run("ROLLBACK", .{});
}

pub fn commit(conn: *Connection) !void {
    try conn.run("COMMIT", .{});
}

/// TODO: create a Stransaction struct with a status enum
pub fn transactionsStatus(conn: *Connection) usize {
    const tx_status = c.PQtransactionStatus(conn.pq_conn);
    return @intCast(tx_status);
}

/// free the memory associated to the Connection
pub fn deinit(conn: *Connection) void {
    c.PQfinish(conn.pq_conn);
}

pub fn lastErrorMsg(conn: *Connection) []const u8 {
    return std.mem.span(c.PQerrorMessage(conn.pq_conn));
}

/// see PQstatus
pub fn status(conn: *Connection) Status {
    return switch (c.PQstatus(conn.pq_conn)) {
        c.CONNECTION_OK => .ok,
        c.CONNECTION_BAD => .bad,
        c.CONNECTION_MADE => .made,
        c.CONNECTION_SETENV => .setenv,
        c.CONNECTION_NEEDED => .needed,
        c.CONNECTION_AUTH_OK => .auth_ok,
        c.CONNECTION_CONSUME => .consume,
        c.CONNECTION_SSL_STARTUP => .ssl_startup,
        else => unreachable,
    };
}

fn execWithoutArgs(conn: *Connection, query: []const u8) !Result {
    const pq_res = c.PQexec(conn.pq_conn, query.ptr);
    errdefer c.PQclear(pq_res);

    try conn.checkResult(pq_res);

    return .{
        .pq_res = pq_res.?,
    };
}

fn checkResult(conn: *Connection, pq_res: ?*c.PGresult) !void {
    const _status = c.PQresultStatus(pq_res);
    if (_status != c.PGRES_TUPLES_OK and _status != c.PGRES_COMMAND_OK) {
        std.log.err("PQerrorMessage: {s} {}\n", .{ c.PQerrorMessage(conn.pq_conn), _status });
        return error.QueryFailed;
    }
}

fn execWithArgs(conn: *Connection, query: []const u8, query_args: anytype) !Result {
    const data = try conn.allocator.alloc([*c]const u8, query_args.len);
    defer conn.allocator.free(data);

    inline for (query_args, 0..) |arg, i| {
        data[i] = arg;
    }

    const pq_res = c.PQexecParams(
        conn.pq_conn,
        query.ptr,
        query_args.len,
        null,
        data.ptr,
        null, // lengths
        null, // format
        0, // txt format
    );
    errdefer c.PQclear(pq_res);

    try conn.checkResult(pq_res);

    return .{
        .pq_res = pq_res.?,
    };
}

/// Executes a query. The memory allocated by exec will be free when deinit is called
pub fn exec(conn: *Connection, query: []const u8, query_args: anytype) !Result {
    errdefer conn.deinit();

    // PQescapeStringConn and PQescapeByteaConn: These functions are used to escape and properly handle strings and bytea data for safe use in SQL queries, preventing SQL injection attacks.
    // const q = c.PQescapeStringConn(conn.pq_conn, query.ptr, query.len);
    if (query_args.len == 0) {
        return try conn.execWithoutArgs(query);
    }

    return try conn.execWithArgs(query, query_args);
}

/// Same as `exec`, but no Result is returned
pub fn run(conn: *Connection, query: []const u8, query_args: anytype) !void {
    var result = try conn.exec(query, query_args);
    try result.checkStatus();
    defer result.deinit();
}

/// Prepares a query;
pub fn prepare(conn: *Connection, stmt_name: []const u8, query: []const u8, n_params: usize) !void {
    const prepare_pq_res = c.PQprepare(conn.pq_conn, stmt_name.ptr, query.ptr, @intCast(n_params), null);
    try conn.checkResult(prepare_pq_res);
    c.PQclear(prepare_pq_res);
}

/// Executes a prepared query
pub fn execPrepared(conn: *Connection, stmt_name: []const u8, params_values: []const []const u8) !Result {
    const data = try conn.allocator.alloc([*c]const u8, params_values.len);
    defer conn.allocator.free(data);

    for (params_values, 0..) |arg, i| {
        data[i] = arg.ptr;
    }

    const pq_res = c.PQexecPrepared(
        conn.pq_conn,
        stmt_name.ptr,
        @intCast(params_values.len),
        data.ptr,
        null,
        null,
        0,
    );
    try conn.checkResult(pq_res);

    return .{ .pq_res = pq_res.? };
}
