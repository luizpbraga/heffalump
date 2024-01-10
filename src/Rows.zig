const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));
const Result = @import("Result.zig");

pub const Rows = @This();
/// DO NOT USE THIS POINTER
res: *Result,
/// DO NOT MODIFY THIS FIELD
max_row_number: usize,
/// DO NOT MODIFY THIS FIELD
max_col_number: usize,
/// DO NOT MODIFY THIS FIELD
current_row: usize = 0,
arena: std.heap.ArenaAllocator,

/// iterate over the rows
pub fn next(rows: *Rows) ?Row {
    if (rows.current_row >= rows.max_row_number) {
        return null;
    }

    const current_row = rows.current_row;
    defer rows.current_row += 1;

    return .{
        .res = rows.res,
        .current_row = current_row,
        .allocator = rows.arena.allocator(),
        .max_col_number = rows.max_col_number,
    };
}

pub fn deinit(rows: *Rows) void {
    rows.arena.deinit();
}

pub fn rollBack(rows: *Rows) void {
    rows.current_row = 0;
}

pub const Row = struct {
    res: *Result,
    current_row: usize,
    max_col_number: usize,
    allocator: std.mem.Allocator,

    fn as(row: *const Row, comptime T: type, value: []const u8) !T {
        // const oid = c.PQftype(row.info.res.pq_res, @intCast(col_idx));
        // std.debug.print("type: {} {}\n", .{ T, @as(Oid, @enumFromInt(oid)) });
        const parsed_value: T = switch (T) {
            usize, u8, u32, u16, u64, u128 => try std.fmt.parseUnsigned(T, value, 10),

            isize, i8, i32, i16, i64, i128 => try std.fmt.parseInt(T, value, 10),

            f16, f32, f64, f128 => try std.fmt.parseFloat(T, value),

            bool => if (std.mem.eql(u8, value, "true")) true else if (std.mem.eql(u8, value, "false")) false else return error.InvalidBooleanFormat,

            []const u8, []u8 => value,

            else => v: {
                if (@typeInfo(T) != .Struct) {
                    return error.ExpectStruct;
                }
                var arena = std.heap.ArenaAllocator.init(row.allocator);
                break :v try std.json.parseFromSliceLeaky(T, arena.allocator(), value, .{});
            },
        };

        return parsed_value;
    }

    /// Iterate over the row; allocate memory ONLY for json objects
    pub fn scan(row: *const Row, args: anytype) !void {
        if (args.len != row.max_col_number) return error.MissingArguments;

        inline for (0..args.len) |col_idx| {
            const value = row.res.getValue(row.current_row, col_idx).?;
            const T = @TypeOf(args[col_idx].*);
            args[col_idx].* = try row.as(T, value);
        }
    }

    /// TODO: fix this
    pub fn get(row: *const Row, comptime T: type, idx_or_name: anytype) !T {
        const K = @TypeOf(idx_or_name);

        const idx = if (K == usize or K == comptime_int)
            idx_or_name
        else if (K == []const u8 or (@typeInfo(@TypeOf(idx_or_name)) == .Pointer)) b: {
            const name = idx_or_name;
            const col = row.res.colNumber(name) orelse return error.UnkowColumnName;
            break :b col;
        } else return error.GetError;

        const value = row.res.getValue(row.current_row, idx).?;
        return try row.as(T, value);
    }

    /// Scans a the struct fields and parse it.
    /// THIS IS BROKEN!!!! I DONT KNOW WHY
    pub fn from(row: *const Row, comptime T: type) !T {
        var t: T = undefined;

        inline for (std.meta.fields(T)) |field| {
            const name = field.name;
            const Ftype = field.type;
            @field(t, name) = try row.get(Ftype, name);
        }

        return t;
    }
};

// THIS API IS DOPE AF
// const conn = ...
//
// const res = try conn.exec(...)
// defer res.deinit()
//
// for (res.rows) |row| {
//     const car = row.from(Car);
//     ...
// }
//
