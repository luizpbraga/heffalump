const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Connector = c.PGconn;
const Result = c.PGresult;
const Row = []const []const u8;
const Table = []const Row;

pub const Record = struct {
    data: Table,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Record) void {
        for (self.data) |lines| {
            self.allocator.free(lines);
        }
        self.allocator.free(self.data);
    }
};

pub const RecordIter = struct {
    n_rows: c_int,
    n_columns: c_int,
    result: ?*Result,
    allocator: std.mem.Allocator,
    row_counter: c_int = 0,
    col_counter: c_int = 0,

    pub fn next(self: *RecordIter) !?Row {
        if (self.row_counter == self.n_rows and self.col_counter == self.col_counter) {
            return null;
        }

        var rows = std.ArrayList([]const u8).init(self.allocator);
        errdefer rows.deinit();

        while (self.col_counter != self.n_columns) : (self.col_counter += 1) {
            const data = std.mem.span(c.PQgetvalue(
                self.result,
                self.row_counter,
                self.col_counter,
            ));

            try rows.append(data);
        }

        if (self.row_counter != self.n_rows) {
            self.row_counter += 1;
            self.col_counter = 0;
        }

        return try rows.toOwnedSlice();
    }
};

pub const Cursor = struct {
    connector: *Connector,
    result: ?*Result = null,

    fn checkResultStatus(result: ?*Result) !void {
        return switch (c.PQresultStatus(result)) {
            c.PGRES_TUPLES_OK,
            c.PGRES_COMMAND_OK,
            c.PGRES_POLLING_OK,
            => {},
            else => error.CommandFailed,
        };
    }

    fn executeWithNoArgs(self: *Cursor, query: []const u8) void {
        self.result = c.PQexec(self.connector, @constCast(query.ptr));
    }

    pub fn execute(self: *Cursor, query: []const u8, args: anytype) !void {
        if (args.len != 0)
            return error.NotSupported;

        self.executeWithNoArgs(query);
        try Cursor.checkResultStatus(self.result);
    }

    // primeira linha
    pub fn fetchOne() void {
        @panic("Not Implemented");
    }

    // um por vez
    pub fn fetchIter(self: *Cursor, allocator: std.mem.Allocator) RecordIter {
        const n_rows = c.PQntuples(self.result);
        const n_columns = c.PQnfields(self.result);

        return .{
            .allocator = allocator,
            .n_rows = n_rows,
            .n_columns = n_columns,
            .result = self.result,
        };
    }

    // tudo
    pub fn fetchAll2() void {
        @panic("Not Implemented");
    }

    pub fn fetchAll(self: *Cursor, allocator: std.mem.Allocator) !Record {
        var c_row: c_int = undefined;
        var c_col: c_int = undefined;
        var rows: std.ArrayList([]const u8) = undefined;
        var table = std.ArrayList([]const []const u8).init(allocator);
        const n_rows: usize = @intCast(c.PQntuples(self.result));
        const n_columns: usize = @intCast(c.PQnfields(self.result));

        if (self.result) |result| {
            for (0..n_rows) |row| {
                c_row = @intCast(row);
                rows = std.ArrayList([]const u8).init(allocator);

                for (0..n_columns) |col| {
                    c_col = @intCast(col);
                    const data = std.mem.span(c.PQgetvalue(result, c_row, c_col));
                    try rows.append(data);
                }

                try table.append(try rows.toOwnedSlice());
            }

            return .{
                .data = try table.toOwnedSlice(),
                .allocator = allocator,
            };
        }

        return error.HollyCow;
    }

    pub fn close(self: *Cursor) void {
        c.PQclear(self.result);
    }

    pub fn next(_: *Cursor) void {
        @panic("Not Implemented");
    }
};

pub const Connection = struct {
    settings: *const ConnectionSetting,
    connector: *Connector,

    pub fn cursor(self: *Connection) Cursor {
        return .{
            .connector = self.connector,
        };
    }

    pub fn close(self: *Connection) void {
        c.PQfinish(self.connector);
    }

    pub fn init(comptime settings: *const ConnectionSetting) !Connection {
        var conn = c.PQconnectdb(settings.connectionString()) orelse return error.CannotConnectToDB;

        if (c.PQstatus(conn) == c.CONNECTION_BAD) {
            const msg = c.PQerrorMessage(conn);
            std.log.err("{s}\n", .{msg});
            return error.CannotOpenDatabase;
        }

        return .{
            .settings = settings,
            .connector = conn,
        };
    }

    pub fn commit(_: *Connector) void {
        @panic("Not Implemented");
    }
};

pub const ConnectionSetting = struct {
    port: []const u8 = "5432",
    user: []const u8 = "postgres",
    host: []const u8 = "localhost",
    dbname: []const u8 = "testdb",
    password: []const u8 = "postgres",

    /// comptime string fmt
    pub fn connectionString(comptime self: *const ConnectionSetting) [*c]const u8 {
        return std.fmt.comptimePrint(
            "user={s} host={s} port={s} dbname={s} password={s}",
            .{ self.user, self.host, self.port, self.dbname, self.password },
        );
    }
};
