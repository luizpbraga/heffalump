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
                const alloc = @constCast(row).allocator;
                break :v try std.json.parseFromSliceLeaky(T, alloc, value, .{});
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

    /// Scans a the struct fields and parse it.
    pub fn scanType(row: *const Row, comptime T: type) !T {
        const t: T = undefined;

        // runtime: vetor de nomes
        // runtime: vetor de colunas
        // runtime: vetor de valores

        const fields = std.meta.fields(T);

        const names, const types = comptime b: {
            var names: [fields.len][]const u8, var types: [fields.len]type = .{ undefined, undefined };
            for (std.meta.fields(T), 0..) |field, i| {
                names[i] = field.name;
                types[i] = field.type;
            }
            break :b .{ names, types };
        };

        _ = types;

        var values = try row.allocator.alloc([]const u8, names.len);
        defer row.allocator.free(values);

        for (names, 0..) |name, i| {
            const col = row.res.colNumber(name).?;
            values[i] = row.res.getValue(row.current_row, col).?;
        }

        // inline for (std.meta.fields(T), 0..) |field, i| {
        //     const name = field.name;
        //     const col = row.res.colNumber(name).?;
        //     const value = row.res.getValue(row.current_row, col).?;
        //     @field(t, name) = try row.as(field.type, value);
        // }

        return t;
    }
};
