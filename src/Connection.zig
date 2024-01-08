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

pub const Info = struct {
    password: []const u8 = "postgres",
    dbname: []const u8 = "testdb",
    user: []const u8 = "postgres",
    host: []const u8 = "localhost",
    port: []const u8 = "5432",

    fn parse(login: *const Info, ally: std.mem.Allocator) ![]const u8 {
        return try std.fmt.allocPrint(ally, "user={s} dbname={s} password={s} host={s} port={s}", .{ login.user, login.dbname, login.password, login.host, login.port });
    }
};

pub const Settings = union(enum) {
    string: []const u8,
    info: Info,
};

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

/// BUG
pub fn init2(allocator: std.mem.Allocator, settings: Settings) (Error || std.fmt.AllocPrintError)!Connection {
    const dsn = switch (settings) {
        .string => |conn_string| conn_string,
        .info => |info| try info.parse(allocator),
    };

    std.debug.print("\n{s}\n", .{dsn});

    defer if (settings == .info) {
        allocator.free(dsn);
    };

    const pq_conn = c.PQconnectdb(dsn.ptr) orelse return error.BadConnection;
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

/// NOT TESTED
pub fn begin(conn: *Connection) !void {
    try conn.run("BEGIN", .{});
}

/// NOT TESTED
pub fn end(conn: *Connection) !void {
    try conn.run("END", .{});
}

/// NOT TESTED
pub fn rollBack(conn: *Connection) !void {
    try conn.run("ROLLBACK", .{});
}

/// NOT TESTED
pub fn commit(conn: *Connection) !void {
    try conn.run("COMMIT", .{});
}

/// NOT TESTED
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

fn execNoParams(conn: *Connection, query: []const u8) !Result {
    const pq_res = c.PQexec(conn.pq_conn, query.ptr);
    errdefer c.PQclear(pq_res);

    try conn.checkResult(pq_res);

    return .{
        .pq_res = pq_res.?,
    };
}

pub fn checkResult(conn: *Connection, pq_res: ?*c.PGresult) !void {
    const _status = c.PQresultStatus(pq_res);
    if (_status != c.PGRES_TUPLES_OK and _status != c.PGRES_COMMAND_OK) {
        std.log.err("PQerrorMessage: {s} {}\n", .{ c.PQerrorMessage(conn.pq_conn), _status });
        return error.QueryFailed;
    }
}

/// Executes using Binary Format. args in query_args may be int, float, string, etc
pub fn execBin(conn: *Connection, query: []const u8, query_args: anytype) !Result {
    const len = query_args.len;
    const param_types = null;
    const param_formats: [len]c_int = .{1} ** len;
    var param_lenghts: [len]c_int = undefined;
    var params_values: [len][*]const u8 = undefined;

    inline for (query_args, &params_values, &param_lenghts) |arg, *d, *lenght| {
        const ArgType = @TypeOf(arg);
        const arg_type_info = @typeInfo(ArgType);

        d.*, lenght.* = switch (arg_type_info) {
            .Pointer => |info| .{
                @ptrCast(arg),
                @sizeOf(@typeInfo(info.child).Array.child) * @typeInfo(info.child).Array.len,
            },
            .Bool => .{
                @ptrCast(&arg),
                @sizeOf(ArgType),
            },
            .Int, .Float => .{
                @ptrCast(&std.mem.bigToNative(ArgType, arg)),
                @sizeOf(ArgType),
            },
            .ComptimeInt => .{
                @ptrCast(&std.mem.bigToNative(i32, arg)),
                @sizeOf(i32),
            },
            .ComptimeFloat => .{
                @ptrCast(&std.mem.bigToNative(f32, arg)),
                @sizeOf(f64),
            },
            else => return error.TypeNotSupportedAsParameter,
        };
    }

    const pq_res = c.PQexecParams(
        conn.pq_conn,
        query.ptr,
        query_args.len,
        param_types,
        &params_values,
        &param_lenghts,
        &param_formats,
        0, // txt format
    );
    errdefer c.PQclear(pq_res);

    try conn.checkResult(pq_res);

    return .{
        .pq_res = pq_res.?,
    };
}

fn execParams(conn: *Connection, query: []const u8, query_args: anytype) !Result {
    const len = query_args.len;
    var params_values: [len][*]const u8 = undefined;

    inline for (&params_values, query_args) |*value, arg| {
        value.* = @alignCast(@ptrCast(arg));
    }

    const pq_res = c.PQexecParams(
        conn.pq_conn,
        query.ptr,
        query_args.len,
        null, // &param_types,
        &params_values,
        null, //param_lenghts, // lengths
        null, //param_formats, // format
        1, // txt format
    );
    errdefer c.PQclear(pq_res);

    try conn.checkResult(pq_res);

    return .{
        .pq_res = pq_res.?,
    };
}

/// Executes a query. The memory allocated by exec will be free when deinit is called
/// Only string data
pub fn exec(conn: *Connection, query: []const u8, query_args: anytype) !Result {
    errdefer conn.deinit();

    // PQescapeStringConn and PQescapeByteaConn: These functions are used to escape and properly handle strings and bytea data for safe use in SQL queries, preventing SQL injection attacks.
    // const q = c.PQescapeStringConn(conn.pq_conn, query.ptr, query.len);
    if (query_args.len == 0) {
        return try conn.execNoParams(query);
    }

    return try conn.execParams(query, query_args);
}

/// Same as `exec`, but no Result is returned
/// Only string data
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

/// Executes a prepared query. Only string data
/// Only string data
pub fn execPrepared(conn: *Connection, stmt_name: []const u8, query_args: anytype) !Result {
    var data: [query_args.len][*]const u8 = undefined;

    inline for (query_args, 0..) |arg, i| {
        data[i] = arg;
    }

    const pq_res = c.PQexecPrepared(
        conn.pq_conn,
        stmt_name.ptr,
        @intCast(query_args.len),
        &data,
        null,
        null,
        0,
    );
    try conn.checkResult(pq_res);

    return .{ .pq_res = pq_res.? };
}
