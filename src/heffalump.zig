const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Connector = c.PGconn;
const Result = c.PGresult;
const Row = []const []const u8;
const Table = []const Row;

pub fn Result2(comptime T: type) type {
    return struct {
        const Self = @This();

        data: if (@typeInfo(T) == .Struct) []const T else []const []const T,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Self) void {
            if (@typeInfo(T) != .Struct)
                for (self.data) |lines| {
                    self.allocator.free(lines);
                };

            self.allocator.free(self.data);
        }
    };
}

pub const Record = struct {
    data: []const []const []const u8,
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

    /// fetches the fist rows only and parses the data
    pub fn fetchOneSameType(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) ![]T {
        const n_columns: usize = @intCast(c.PQnfields(self.result));
        var counter: c_int = 0;
        var result = try allocator.alloc(T, n_columns);
        errdefer allocator.free(result);

        while (counter < n_columns) : (counter += 1) {
            const data = std.mem.span(c.PQgetvalue(self.result, 0, counter));
            var i: usize = @intCast(counter);
            switch (T) {
                comptime_int, i32, usize, i64 => {
                    result[i] = try std.fmt.parseInt(T, data, 10);
                },
                u8, []u8, []const u8 => {
                    result[i] = data;
                },
                comptime_float, f32, f64 => {
                    result[i] = try std.fmt.parseFloat(T, data);
                },

                else => {
                    std.log.err("Note: type is {}", .{T});
                    return error.CannotParseThisType;
                },
            }
        }

        return result;
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

    /// parse primitive values
    fn parse(comptime T: type, data: []const u8) !T {
        return switch (@typeInfo(T)) {
            .Null => null,
            .Bool => data[0] == 't',
            .Int => try std.fmt.parseInt(T, data, 10),
            .Float => try std.fmt.parseFloat(T, data),
            else => {
                if (std.meta.trait.isZigString(T))
                    return data;

                if (std.meta.trait.isSlice(T))
                    return error.NotImplemented;

                return data;
            },
        };
    }

    pub fn fetchStruct(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) !Result2(T) {
        // const column_name = c.PQfname(result, c_col);
        // const column_number = c.PQfnumber(result, column_name);
        // const column_type = c.PQftype(result, c_col);
        //TODO: see c.PQgetisnull
        var c_row: c_int = undefined;
        var c_col: c_int = undefined;
        var table = std.ArrayList(T).init(allocator);
        const n_rows: usize = @intCast(c.PQntuples(self.result));
        const n_columns: usize = @intCast(c.PQnfields(self.result));
        const result = self.result orelse return error.NoDataToFetch;
        const fields = std.meta.fields(T);

        for (0..n_rows) |row| {
            c_row = @intCast(row);

            var t: T = undefined;
            inline for (fields, 0..n_columns) |field, col| {
                c_col = @intCast(col);

                const data = std.mem.span(c.PQgetvalue(result, c_row, c_col));
                @field(t, field.name) = try Cursor.parse(field.type, data);
            }
            try table.append(t);
        }

        return .{
            .data = try table.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    fn fetchPrimitive(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) !Result2(T) {
        //TODO: see c.PQgetisnull
        var c_row: c_int = undefined;
        var c_col: c_int = undefined;
        var rows: std.ArrayList(T) = undefined;
        var table = std.ArrayList([]const T).init(allocator);
        const n_rows: usize = @intCast(c.PQntuples(self.result));
        const n_columns: usize = @intCast(c.PQnfields(self.result));
        const result = self.result orelse return error.NoDataToFetch;

        for (0..n_rows) |row| {
            c_row = @intCast(row);
            rows = std.ArrayList(T).init(allocator);

            for (0..n_columns) |col| {
                c_col = @intCast(col);
                const data = std.mem.span(c.PQgetvalue(result, c_row, c_col));
                const value = try Cursor.parse(T, data);
                try rows.append(value);
            }

            try table.append(try rows.toOwnedSlice());
        }

        return .{
            .data = try table.toOwnedSlice(),
            .allocator = allocator,
        };
    }

    pub fn fetchTuple(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) !Result2(T) {
        _ = allocator;
        _ = self;
        @compileError("Not Implemented");
    }
    pub fn fetchArray(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) !Result2(T) {
        _ = allocator;
        _ = self;
        @compileError("Not Implemented");
    }

    pub fn fetch(self: *Cursor, allocator: std.mem.Allocator, comptime T: type) !Result2(T) {
        // TODO: Handle All Possibilities

        const info = @typeInfo(T);

        if (info == .Struct and !info.Struct.is_tuple)
            return try self.fetchStruct(allocator, T);

        if (info == .Struct and info.Struct.is_tuple)
            return try self.fetchStruct(allocator, T);

        if (info == .Array)
            return try self.fetchStruct(allocator, T);

        return try self.fetchPrimitive(allocator, T);
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

        return error.NotDataToFetch;
    }

    pub fn deinit(self: *Cursor) void {
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

    pub fn deinit(self: *Connection) void {
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

const ConnectionKeys = enum {
    port,
    user,
    dbname,
    password,
    host,
};

const EnvironmentName = []const u8;
const ConnectionMap = std.ComptimeStringMap(ConnectionKeys, EnvironmentName);

pub const ConnectionSetting = struct {
    port: ?[]const u8 = "5432",
    user: ?[]const u8 = "postgres",
    host: ?[]const u8 = "localhost",
    dbname: ?[]const u8 = "testdb",
    password: ?[]const u8 = "postgres",

    fn initEmpty() ConnectionSetting {
        return .{ .port = "", .user = "", .host = "", .dbname = "", .password = "" };
    }

    /// comptime string fmt
    pub fn connectionString(comptime self: *const ConnectionSetting) [*c]const u8 {
        return std.fmt.comptimePrint(
            "user={s} host={s} port={s} dbname={s} password={s}",
            .{ self.user orelse "", self.host orelse "", self.port orelse "", self.dbname orelse "", self.password orelse "" },
        );
    }
};

test "parse single value" {
    const allocator = std.testing.allocator;
    const settings = ConnectionSetting{};

    var conn = try Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    const Test = struct {
        Type: type,
        query: []const u8,
    };

    const values = .{ 1, 1.0, "ola mundo" };
    const tests = [_]Test{
        .{ .Type = usize, .query = "select 1" },
        .{ .Type = f32, .query = "select 1.0" },
        .{ .Type = []const u8, .query = "select 'ola mundo'" },
    };

    inline for (tests, values) |t, val| {
        try cur.execute(t.query, .{});
        {
            var data = try cur.fetchOneSameType(allocator, t.Type);
            defer allocator.free(data);
            try std.testing.expect(data.len == 1);

            if (t.Type != []const u8)
                try std.testing.expect(val == data[0]);

            if (t.Type == []const u8)
                try std.testing.expect(std.mem.eql(u8, data[0], val));
        }
    }
}

test "parse mult value" {
    const allocator = std.testing.allocator;
    const settings = ConnectionSetting{};

    var conn = try Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    try cur.execute("select 1, 2, 3, 4, 5", .{});
    {
        var data = try cur.fetchOneSameType(allocator, usize);
        defer allocator.free(data);
        try std.testing.expect(data.len == 5);
        try std.testing.expect(1 == data[0]);
        try std.testing.expect(2 == data[1]);
        try std.testing.expect(3 == data[2]);
        try std.testing.expect(4 == data[3]);
        try std.testing.expect(5 == data[4]);
    }
}

test "parse mult value T\n" {
    const allocator = std.testing.allocator;
    const settings = ConnectionSetting{};

    var conn = try Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    try cur.execute("select (1,1,1,1)", .{});
    {
        var result = try cur.fetch(allocator, []const u8);
        defer result.deinit();
        var data = result.data;

        for (data) |row|
            std.debug.print("{d}\n", .{row});
    }
}

test "parse Cars\n" {
    const allocator = std.testing.allocator;
    const settings = ConnectionSetting{};

    var conn = try Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    const Car = struct {
        id: usize,
        name: []const u8,
        price: usize,
    };

    try cur.execute("select * from Cars", .{});
    {
        var result = try cur.fetch(allocator, Car);
        defer result.deinit();

        for (result.data) |car| {
            std.debug.print("id: {}, name: {s}, price: ${}\n", .{ car.id, car.name, car.price });
        }
    }
}

test "Record(T)" {
    {
        const RecordUsize = Result2(usize);
        var r = RecordUsize{ .data = undefined, .allocator = undefined };
        try std.testing.expect(@TypeOf(r.data) == []const []const usize);
    }
    {
        const RecordSliceUsize = Result2([]usize);
        var r = RecordSliceUsize{ .data = undefined, .allocator = undefined };
        try std.testing.expect(@TypeOf(r.data) == []const []const []usize);
    }
    {
        const T = struct { usize, i32, f64 };
        const RecordStruct = Result2(T);
        var r = RecordStruct{ .data = undefined, .allocator = undefined };
        try std.testing.expect(@TypeOf(r.data) == []const T);
    }
}

test "return one row aka []const T\n" {
    const allocator = std.testing.allocator;
    const settings = ConnectionSetting{};

    var conn = try Connection.init(&settings);
    defer conn.deinit();

    var cur = conn.cursor();
    defer cur.deinit();

    try cur.execute("select 1, 2, 3, 4, 5", .{});
    {
        var result = try cur.fetch(allocator, usize);
        defer result.deinit();

        var data = result.data;

        for (data) |row| {
            try std.testing.expect([]const usize == @TypeOf(row));
            std.debug.print("{d}\n", .{row});
        }
    }
}

test "load" {
    const getenv = std.os.getenv;

    const settings = ConnectionSetting{
        .port = getenv("DB_PORT"),
        .user = getenv("DB_USER"),
        .host = getenv("DB_HOST"),
        .dbname = getenv("DB_NAME"),
        .password = getenv("DB_PASSWORD"),
    };

    _ = settings;
}
