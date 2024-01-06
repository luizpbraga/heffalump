const std = @import("std");
const c = @cImport(@cInclude("libpq-fe.h"));

pub const Rows = struct {
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

        defer rows.current_row += 1;
        return .{ .info = rows.* };
    }

    pub fn rollBack(rows: *Rows) void {
        rows.current_row = 0;
    }

    pub const Row = struct {
        info: Rows,

        /// iterate over the row; allocate memory ONLY for json objects
        pub fn scan(row: *const Row, args: anytype) !void {
            if (args.len != row.info.max_col_number) return error.MissingArguments;

            inline for (0..args.len) |col_idx| {
                const value = row.info.res.getValue(row.info.current_row, col_idx).?;
                const T = @TypeOf(args[col_idx].*);
                // const oid = c.PQftype(row.info.res.pq_res, @intCast(col_idx));
                // std.debug.print("type: {} {}\n", .{ T, @as(Oid, @enumFromInt(oid)) });

                const parsed_value: T = switch (T) {
                    usize, u8, u32, u16, u64, u128 => try std.fmt.parseUnsigned(T, value, 10),
                    isize, i8, i32, i16, i64, i128 => try std.fmt.parseInt(T, value, 10),
                    f16, f32, f64, f128 => try std.fmt.parseFloat(T, value),
                    bool => if (std.mem.eql(u8, value, "true"))
                        true
                    else if (std.mem.eql(u8, value, "false"))
                        false
                    else
                        return error.InvalidBooleanFormat,
                    []const u8, []u8 => value,
                    else => v: {
                        if (@typeInfo(T) != .Struct) {
                            return error.ExpectStruct;
                        }
                        const alloc = row.info.arena.allocator();
                        break :v try std.json.parseFromSliceLeaky(T, alloc, value, .{});
                    },
                };

                args[col_idx].* = parsed_value;
            }
        }

        pub fn parse(row: *const Row, comptime T: type) !T {
            var t: T = undefined;
            const fields = std.meta.fields(T);
            inline for (fields) |field| {
                const name = field.name;
                const col = row.info.res.colNumber(name) orelse 0;
                const value = row.info.res.getValue(row.info.current_row, col).?;
                @field(t, name) = value;
            }
            return t;
        }
    };
};

pub const Result = struct {
    /// DO NOT USE THIS POINTER
    pq_res: *c.PGresult,

    pub const Status = enum {
        tuples_ok,
        command_ok,
        polling_ok,
    };

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

    pub fn deinit(res: *Result) void {
        c.PQclear(res.pq_res);
    }

    pub fn nRows(res: *Result) usize {
        return @intCast(c.PQntuples(res.pq_res));
    }

    pub fn nCols(result: *Result) usize {
        return @intCast(c.PQnfields(result.pq_res));
    }

    pub fn colName(result: *Result, col_number: usize) []const u8 {
        const c_col_number: c_int = @intCast(col_number);
        return std.mem.span(c.PQfname(result.pq_res, c_col_number));
    }

    pub fn colNumber(result: *Result, col_name: []const u8) ?usize {
        const col = c.PQfnumber(result.pq_res, col_name.ptr);
        return if (col == -1) null else @intCast(col);
    }

    pub fn colType(result: *Result, col_number: usize) usize {
        const c_col_number: c_int = @intCast(col_number);
        return @intCast(c.PQftype(result.pq_res, c_col_number));
    }

    pub fn colTypeName(result: *Result, col_number: usize) []const u8 {
        const c_col_number: c_int = @intCast(col_number);
        return @intCast(c.PQftypeName(result.pq_res, c_col_number));
    }

    pub fn printResult(result: *Result) void {
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
                std.log.err(">>{}\n", .{s});
                break :b error.CommandFailed;
            },
        };
    }

    pub fn status(res: *Result) Status {
        return switch (c.PQresultStatus(res.pg_res)) {
            c.PGRES_TUPLES_OK => .tuples_ok,
            c.PGRES_COMMAND_OK => .command_ok,
            c.PGRES_POLLING_OK => .polling_ok,
            else => unreachable,
        };
    }
};

/// We use Transaction when the database state can be changed
/// COMMIT, BEGIN AND ROLLBACK
// pub const Transaction = struct {
//     conn: *Connection,
//
//     pub const Status = enum {
//         /// A command is in progress. Only when a query has been sent to the server and not yet completed.
//         active,
//         /// Currently idle
//         idle,
//         /// Idle, in a valid transaction block.
//         intrans,
//         /// Idle, in a failed transaction block.
//         inerror,
//         /// Connection is bad.
//         unknown,
//     };
//
//     /// Returns the current in-transaction status of the server.
//     pub fn status(tx: *const Transaction) Status {
//         return switch (c.PQtransactionStatus(tx.conn)) {
//             c.PQTRANS_IDLE => .idle,
//             c.PQTRANS_ACTIVE => .active,
//             c.PQTRANS_INERROR => .inerror,
//             c.PQTRANS_UNKNOWN => .unknown,
//             c.PQTRANS_INTRANS => .intrans,
//             else => unreachable,
//         };
//     }
//
//     fn begin(conn: *Connection) !Transaction {
//         var res = conn.exec("select count(*) from cars;");
//         defer res.deinit();
//     }
//
//     fn commit(tx: *Transaction) !void {
//         _ = tx;
//     }
//
//     fn rollBack(tx: *Transaction) !void {
//         _ = tx;
//     }
// };

pub const Connection = struct {
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
            std.log.err("{s}", .{c.PQerrorMessage(pq_conn)});
            return error.ConnectionFailed;
        }

        return .{
            .allocator = allocator,
            .pq_conn = pq_conn,
        };
    }

    pub fn begin(conn: *Connection) !void {
        var res = try conn.exec("BEGIN", .{});
        defer res.deinit();
        try res.checkStatus();
        return res;
    }

    pub fn end(conn: *Connection) !void {
        var res = try conn.exec("end", .{});
        defer res.deinit();
        try res.checkStatus();
    }

    pub fn rollBack(conn: *Connection) !void {
        var res = try conn.exec("ROLLBACK", .{});
        defer res.deinit();
        try res.checkStatus();
    }

    pub fn commit(conn: *Connection) !void {
        var res = try conn.exec("COMMIT", .{});
        defer res.deinit();
        try res.checkStatus();
    }

    /// free the memory associated to the Connection
    pub fn deinit(conn: *Connection) void {
        c.PQfinish(conn.pq_conn);
    }

    /// see PQstatus
    pub fn status(conn: *Connection) Status {
        return switch (c.PQstatus(conn.pg_conn)) {
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

        if (c.PQresultStatus(pq_res) != c.PGRES_TUPLES_OK) {
            std.log.err("{s}", .{c.PQerrorMessage(conn.pq_conn)});
            return error.QueryFailed;
        }

        return .{
            .pq_res = pq_res.?,
        };
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
            0,
        );
        errdefer c.PQclear(pq_res);

        if (c.PQresultStatus(pq_res) != c.PGRES_TUPLES_OK) {
            std.log.err("{s}", .{c.PQerrorMessage(conn.pq_conn)});
            return error.QueryFailed;
        }

        return .{
            .pq_res = pq_res.?,
        };
    }

    /// the memory allocated by exec will be free when deinit is called
    pub fn exec(conn: *Connection, query: []const u8, query_args: anytype) !Result {
        errdefer conn.deinit();

        if (query_args.len == 0) {
            return try conn.execWithoutArgs(query);
        }

        return try conn.execWithArgs(query, query_args);
    }

    pub fn execAlloc(conn: *Connection, allocator: std.mem.Allocator, query: []const u8, query_args: anytype) Result {
        _ = allocator;
        _ = conn;
        _ = query_args;
        _ = query;

        return .{};
    }
};

pub fn main() !void {}

pub const Oid = enum(u16) {
    bool = 16,
    bytea = 17,
    char = 18,
    name = 19,
    int8 = 20,
    int2 = 21,
    int2vector = 22,
    int4 = 23,
    regproc = 24,
    text = 25,
    oid = 26,
    tid = 27,
    xid = 28,
    cid = 29,
    oidvector = 30,
    pg_type = 71,
    pg_attribute = 75,
    pg_proc = 81,
    pg_class = 83,
    json = 114,
    xml = 142,
    pg_node_tree = 194,
    pg_ndistinct = 3361,
    pg_dependencies = 3402,
    pg_mcv_list = 5017,
    pg_ddl_command = 32,
    xid8 = 5069,
    point = 600,
    lseg = 601,
    path = 602,
    box = 603,
    polygon = 604,
    line = 628,
    float4 = 700,
    float8 = 701,
    unknown = 705,
    circle = 718,
    money = 790,
    macaddr = 829,
    inet = 869,
    cidr = 650,
    macaddr8 = 774,
    aclitem = 1033,
    bpchar = 1042,
    varchar = 1043,
    date = 1082,
    time = 1083,
    timestamp = 1114,
    timestamptz = 1184,
    interval = 1186,
    timetz = 1266,
    bit = 1560,
    varbit = 1562,
    numeric = 1700,
    refcursor = 1790,
    regprocedure = 2202,
    regoper = 2203,
    regoperator = 2204,
    regclass = 2205,
    regcollation = 4191,
    regtype = 2206,
    regrole = 4096,
    regnamespace = 4089,
    uuid = 2950,
    pg_lsn = 3220,
    tsvector = 3614,
    gtsvector = 3642,
    tsquery = 3615,
    regconfig = 3734,
    regdictionary = 3769,
    jsonb = 3802,
    jsonpath = 4072,
    txid_snapshot = 2970,
    pg_snapshot = 5038,
    int4range = 3904,
    numrange = 3906,
    tsrange = 3908,
    tstzrange = 3910,
    daterange = 3912,
    int8range = 3926,
    int4multirange = 4451,
    nummultirange = 4532,
    tsmultirange = 4533,
    tstzmultirange = 4534,
    datemultirange = 4535,
    int8multirange = 4536,
    record = 2249,
    _record = 2287,
    cstring = 2275,
    any = 2276,
    anyarray = 2277,
    void = 2278,
    trigger = 2279,
    event_trigger = 3838,
    language_handler = 2280,
    internal = 2281,
    anyelement = 2283,
    anynonarray = 2776,
    anyenum = 3500,
    fdw_handler = 3115,
    index_am_handler = 325,
    tsm_handler = 3310,
    table_am_handler = 269,
    anyrange = 3831,
    anycompatible = 5077,
    anycompatiblearray = 5078,
    anycompatiblenonarray = 5079,
    anycompatiblerange = 5080,
    anymultirange = 4537,
    anycompatiblemultirange = 4538,
    pg_brin_bloom_summary = 4600,
    pg_brin_minmax_multi_summary = 4601,
    _bool = 1000,
    _bytea = 1001,
    _char = 1002,
    _name = 1003,
    _int8 = 1016,
    _int2 = 1005,
    _int2vector = 1006,
    _int4 = 1007,
    _regproc = 1008,
    _text = 1009,
    _oid = 1028,
    _tid = 1010,
    _xid = 1011,
    _cid = 1012,
    _oidvector = 1013,
    _pg_type = 210,
    _pg_attribute = 270,
    _pg_proc = 272,
    _pg_class = 273,
    _json = 199,
    _xml = 143,
    _xid8 = 271,
    _point = 1017,
    _lseg = 1018,
    _path = 1019,
    _box = 1020,
    _polygon = 1027,
    _line = 629,
    _float4 = 1021,
    _float8 = 1022,
    _circle = 719,
    _money = 791,
    _macaddr = 1040,
    _inet = 1041,
    _cidr = 651,
    _macaddr8 = 775,
    _aclitem = 1034,
    _bpchar = 1014,
    _varchar = 1015,
    _date = 1182,
    _time = 1183,
    _timestamp = 1115,
    _timestamptz = 1185,
    _interval = 1187,
    _timetz = 1270,
    _bit = 1561,
    _varbit = 1563,
    _numeric = 1231,
    _refcursor = 2201,
    _regprocedure = 2207,
    _regoper = 2208,
    _regoperator = 2209,
    _regclass = 2210,
    _regcollation = 4192,
    _regtype = 2211,
    _regrole = 4097,
    _regnamespace = 4090,
    _uuid = 2951,
    _pg_lsn = 3221,
    _tsvector = 3643,
    _gtsvector = 3644,
    _tsquery = 3645,
    _regconfig = 3735,
    _regdictionary = 3770,
    _jsonb = 3807,
    _jsonpath = 4073,
    _txid_snapshot = 2949,
    _pg_snapshot = 5039,
    _int4range = 3905,
    _numrange = 3907,
    _tsrange = 3909,
    _tstzrange = 3911,
    _daterange = 3913,
    _int8range = 3927,
    _int4multirange = 6150,
    _nummultirange = 6151,
    _tsmultirange = 6152,
    _tstzmultirange = 6153,
    _datemultirange = 6155,
    _int8multirange = 6157,
    _cstring = 1263,
    pg_attrdef = 12001,
    _pg_attrdef = 12000,
    pg_constraint = 12003,
    _pg_constraint = 12002,
    pg_inherits = 12005,
    _pg_inherits = 12004,
    pg_index = 12007,
    _pg_index = 12006,
    pg_operator = 12009,
    _pg_operator = 12008,
    pg_opfamily = 12011,
    _pg_opfamily = 12010,
    pg_opclass = 12013,
    _pg_opclass = 12012,
    pg_am = 12015,
    _pg_am = 12014,
    pg_amop = 12017,
    _pg_amop = 12016,
    pg_amproc = 12019,
    _pg_amproc = 12018,
    pg_language = 12021,
    _pg_language = 12020,
    pg_largeobject_metadata = 12023,
    _pg_largeobject_metadata = 12022,
    pg_largeobject = 12025,
    _pg_largeobject = 12024,
    pg_aggregate = 12027,
    _pg_aggregate = 12026,
    pg_statistic = 12029,
    _pg_statistic = 12028,
    pg_statistic_ext = 12031,
    _pg_statistic_ext = 12030,
    pg_statistic_ext_data = 12033,
    _pg_statistic_ext_data = 12032,
    pg_rewrite = 12035,
    _pg_rewrite = 12034,
    pg_trigger = 12037,
    _pg_trigger = 12036,
    pg_event_trigger = 12039,
    _pg_event_trigger = 12038,
    pg_description = 12041,
    _pg_description = 12040,
    pg_cast = 12043,
    _pg_cast = 12042,
    pg_enum = 12045,
    _pg_enum = 12044,
    pg_namespace = 12047,
    _pg_namespace = 12046,
    pg_conversion = 12049,
    _pg_conversion = 12048,
    pg_depend = 12051,
    _pg_depend = 12050,
    pg_database = 1248,
    _pg_database = 12052,
    pg_db_role_setting = 12054,
    _pg_db_role_setting = 12053,
    pg_tablespace = 12056,
    _pg_tablespace = 12055,
    pg_authid = 2842,
    _pg_authid = 12057,
    pg_auth_members = 2843,
    _pg_auth_members = 12058,
    pg_shdepend = 12060,
    _pg_shdepend = 12059,
    pg_shdescription = 12062,
    _pg_shdescription = 12061,
    pg_ts_config = 12064,
    _pg_ts_config = 12063,
    pg_ts_config_map = 12066,
    _pg_ts_config_map = 12065,
    pg_ts_dict = 12068,
    _pg_ts_dict = 12067,
    pg_ts_parser = 12070,
    _pg_ts_parser = 12069,
    pg_ts_template = 12072,
    _pg_ts_template = 12071,
    pg_extension = 12074,
    _pg_extension = 12073,
    pg_foreign_data_wrapper = 12076,
    _pg_foreign_data_wrapper = 12075,
    pg_foreign_server = 12078,
    _pg_foreign_server = 12077,
    pg_user_mapping = 12080,
    _pg_user_mapping = 12079,
    pg_foreign_table = 12082,
    _pg_foreign_table = 12081,
    pg_policy = 12084,
    _pg_policy = 12083,
    pg_replication_origin = 12086,
    _pg_replication_origin = 12085,
    pg_default_acl = 12088,
    _pg_default_acl = 12087,
    pg_init_privs = 12090,
    _pg_init_privs = 12089,
    pg_seclabel = 12092,
    _pg_seclabel = 12091,
    pg_shseclabel = 4066,
    _pg_shseclabel = 12093,
    pg_collation = 12095,
    _pg_collation = 12094,
    pg_partitioned_table = 12097,
    _pg_partitioned_table = 12096,
    pg_range = 12099,
    _pg_range = 12098,
    pg_transform = 12101,
    _pg_transform = 12100,
    pg_sequence = 12103,
    _pg_sequence = 12102,
    pg_publication = 12105,
    _pg_publication = 12104,
    pg_publication_rel = 12107,
    _pg_publication_rel = 12106,
    pg_subscription = 6101,
    _pg_subscription = 12108,
    pg_subscription_rel = 12110,
    _pg_subscription_rel = 12109,
    pg_roles = 12219,
    _pg_roles = 12218,
    pg_shadow = 12224,
    _pg_shadow = 12223,
    pg_group = 12229,
    _pg_group = 12228,
    pg_user = 12233,
    _pg_user = 12232,
    pg_policies = 12237,
    _pg_policies = 12236,
    pg_rules = 12242,
    _pg_rules = 12241,
    pg_views = 12247,
    _pg_views = 12246,
    pg_tables = 12252,
    _pg_tables = 12251,
    pg_matviews = 12257,
    _pg_matviews = 12256,
    pg_indexes = 12262,
    _pg_indexes = 12261,
    pg_sequences = 12267,
    _pg_sequences = 12266,
    pg_stats = 12272,
    _pg_stats = 12271,
    pg_stats_ext = 12277,
    _pg_stats_ext = 12276,
    pg_stats_ext_exprs = 12282,
    _pg_stats_ext_exprs = 12281,
    pg_publication_tables = 12287,
    _pg_publication_tables = 12286,
    pg_locks = 12292,
    _pg_locks = 12291,
    pg_cursors = 12296,
    _pg_cursors = 12295,
    pg_available_extensions = 12300,
    _pg_available_extensions = 12299,
    pg_available_extension_versions = 12304,
    _pg_available_extension_versions = 12303,
    pg_prepared_xacts = 12309,
    _pg_prepared_xacts = 12308,
    pg_prepared_statements = 12314,
    _pg_prepared_statements = 12313,
    pg_seclabels = 12318,
    _pg_seclabels = 12317,
    pg_settings = 12323,
    _pg_settings = 12322,
    pg_file_settings = 12329,
    _pg_file_settings = 12328,
    pg_hba_file_rules = 12333,
    _pg_hba_file_rules = 12332,
    pg_timezone_abbrevs = 12337,
    _pg_timezone_abbrevs = 12336,
    pg_timezone_names = 12341,
    _pg_timezone_names = 12340,
    pg_config = 12345,
    _pg_config = 12344,
    pg_shmem_allocations = 12349,
    _pg_shmem_allocations = 12348,
    pg_backend_memory_contexts = 12353,
    _pg_backend_memory_contexts = 12352,
    pg_stat_all_tables = 12357,
    _pg_stat_all_tables = 12356,
    pg_stat_xact_all_tables = 12362,
    _pg_stat_xact_all_tables = 12361,
    pg_stat_sys_tables = 12367,
    _pg_stat_sys_tables = 12366,
    pg_stat_xact_sys_tables = 12372,
    _pg_stat_xact_sys_tables = 12371,
    pg_stat_user_tables = 12376,
    _pg_stat_user_tables = 12375,
    pg_stat_xact_user_tables = 12381,
    _pg_stat_xact_user_tables = 12380,
    pg_statio_all_tables = 12385,
    _pg_statio_all_tables = 12384,
    pg_statio_sys_tables = 12390,
    _pg_statio_sys_tables = 12389,
    pg_statio_user_tables = 12394,
    _pg_statio_user_tables = 12393,
    pg_stat_all_indexes = 12398,
    _pg_stat_all_indexes = 12397,
    pg_stat_sys_indexes = 12403,
    _pg_stat_sys_indexes = 12402,
    pg_stat_user_indexes = 12407,
    _pg_stat_user_indexes = 12406,
    pg_statio_all_indexes = 12411,
    _pg_statio_all_indexes = 12410,
    pg_statio_sys_indexes = 12416,
    _pg_statio_sys_indexes = 12415,
    pg_statio_user_indexes = 12420,
    _pg_statio_user_indexes = 12419,
    pg_statio_all_sequences = 12424,
    _pg_statio_all_sequences = 12423,
    pg_statio_sys_sequences = 12429,
    _pg_statio_sys_sequences = 12428,
    pg_statio_user_sequences = 12433,
    _pg_statio_user_sequences = 12432,
    pg_stat_activity = 12437,
    _pg_stat_activity = 12436,
    pg_stat_replication = 12442,
    _pg_stat_replication = 12441,
    pg_stat_slru = 12447,
    _pg_stat_slru = 12446,
    pg_stat_wal_receiver = 12451,
    _pg_stat_wal_receiver = 12450,
    pg_stat_subscription = 12455,
    _pg_stat_subscription = 12454,
    pg_stat_ssl = 12460,
    _pg_stat_ssl = 12459,
    pg_stat_gssapi = 12464,
    _pg_stat_gssapi = 12463,
    pg_replication_slots = 12468,
    _pg_replication_slots = 12467,
    pg_stat_replication_slots = 12473,
    _pg_stat_replication_slots = 12472,
    pg_stat_database = 12477,
    _pg_stat_database = 12476,
    pg_stat_database_conflicts = 12482,
    _pg_stat_database_conflicts = 12481,
    pg_stat_user_functions = 12486,
    _pg_stat_user_functions = 12485,
    pg_stat_xact_user_functions = 12491,
    _pg_stat_xact_user_functions = 12490,
    pg_stat_archiver = 12496,
    _pg_stat_archiver = 12495,
    pg_stat_bgwriter = 12500,
    _pg_stat_bgwriter = 12499,
    pg_stat_wal = 12504,
    _pg_stat_wal = 12503,
    pg_stat_progress_analyze = 12508,
    _pg_stat_progress_analyze = 12507,
    pg_stat_progress_vacuum = 12513,
    _pg_stat_progress_vacuum = 12512,
    pg_stat_progress_cluster = 12518,
    _pg_stat_progress_cluster = 12517,
    pg_stat_progress_create_index = 12523,
    _pg_stat_progress_create_index = 12522,
    pg_stat_progress_basebackup = 12528,
    _pg_stat_progress_basebackup = 12527,
    pg_stat_progress_copy = 12533,
    _pg_stat_progress_copy = 12532,
    pg_user_mappings = 12538,
    _pg_user_mappings = 12537,
    pg_replication_origin_status = 12543,
    _pg_replication_origin_status = 12542,
    cardinal_number = 13430,
    _cardinal_number = 13429,
    character_data = 13433,
    _character_data = 13432,
    sql_identifier = 13435,
    _sql_identifier = 13434,
    information_schema_catalog_name = 13438,
    _information_schema_catalog_name = 13437,
    time_stamp = 13441,
    _time_stamp = 13440,
    yes_or_no = 13443,
    _yes_or_no = 13442,
    applicable_roles = 13447,
    _applicable_roles = 13446,
    administrable_role_authorizations = 13452,
    _administrable_role_authorizations = 13451,
    attributes = 13456,
    _attributes = 13455,
    character_sets = 13461,
    _character_sets = 13460,
    check_constraint_routine_usage = 13466,
    _check_constraint_routine_usage = 13465,
    check_constraints = 13471,
    _check_constraints = 13470,
    collations = 13476,
    _collations = 13475,
    collation_character_set_applicability = 13481,
    _collation_character_set_applicability = 13480,
    column_column_usage = 13486,
    _column_column_usage = 13485,
    column_domain_usage = 13491,
    _column_domain_usage = 13490,
    column_privileges = 13496,
    _column_privileges = 13495,
    column_udt_usage = 13501,
    _column_udt_usage = 13500,
    columns = 13506,
    _columns = 13505,
    constraint_column_usage = 13511,
    _constraint_column_usage = 13510,
    constraint_table_usage = 13516,
    _constraint_table_usage = 13515,
    domain_constraints = 13521,
    _domain_constraints = 13520,
    domain_udt_usage = 13526,
    _domain_udt_usage = 13525,
    domains = 13531,
    _domains = 13530,
    enabled_roles = 13536,
    _enabled_roles = 13535,
    key_column_usage = 13540,
    _key_column_usage = 13539,
    parameters = 13545,
    _parameters = 13544,
    referential_constraints = 13550,
    _referential_constraints = 13549,
    role_column_grants = 13555,
    _role_column_grants = 13554,
    routine_column_usage = 13559,
    _routine_column_usage = 13558,
    routine_privileges = 13564,
    _routine_privileges = 13563,
    role_routine_grants = 13569,
    _role_routine_grants = 13568,
    routine_routine_usage = 13573,
    _routine_routine_usage = 13572,
    routine_sequence_usage = 13578,
    _routine_sequence_usage = 13577,
    routine_table_usage = 13583,
    _routine_table_usage = 13582,
    routines = 13588,
    _routines = 13587,
    schemata = 13593,
    _schemata = 13592,
    sequences = 13597,
    _sequences = 13596,
    sql_features = 13602,
    _sql_features = 13601,
    sql_implementation_info = 13607,
    _sql_implementation_info = 13606,
    sql_parts = 13612,
    _sql_parts = 13611,
    sql_sizing = 13617,
    _sql_sizing = 13616,
    table_constraints = 13622,
    _table_constraints = 13621,
    table_privileges = 13627,
    _table_privileges = 13626,
    role_table_grants = 13632,
    _role_table_grants = 13631,
    tables = 13636,
    _tables = 13635,
    transforms = 13641,
    _transforms = 13640,
    triggered_update_columns = 13646,
    _triggered_update_columns = 13645,
    triggers = 13651,
    _triggers = 13650,
    udt_privileges = 13656,
    _udt_privileges = 13655,
    role_udt_grants = 13661,
    _role_udt_grants = 13660,
    usage_privileges = 13665,
    _usage_privileges = 13664,
    role_usage_grants = 13670,
    _role_usage_grants = 13669,
    user_defined_types = 13674,
    _user_defined_types = 13673,
    view_column_usage = 13679,
    _view_column_usage = 13678,
    view_routine_usage = 13684,
    _view_routine_usage = 13683,
    view_table_usage = 13689,
    _view_table_usage = 13688,
    views = 13694,
    _views = 13693,
    data_type_privileges = 13699,
    _data_type_privileges = 13698,
    element_types = 13704,
    _element_types = 13703,
    _pg_foreign_table_columns = 13709,
    __pg_foreign_table_columns = 13708,
    column_options = 13714,
    _column_options = 13713,
    _pg_foreign_data_wrappers = 13718,
    __pg_foreign_data_wrappers = 13717,
    foreign_data_wrapper_options = 13722,
    _foreign_data_wrapper_options = 13721,
    foreign_data_wrappers = 13726,
    _foreign_data_wrappers = 13725,
    _pg_foreign_servers = 13730,
    __pg_foreign_servers = 13729,
    foreign_server_options = 13735,
    _foreign_server_options = 13734,
    foreign_servers = 13739,
    _foreign_servers = 13738,
    _pg_foreign_tables = 13743,
    __pg_foreign_tables = 13742,
    foreign_table_options = 13748,
    _foreign_table_options = 13747,
    foreign_tables = 13752,
    _foreign_tables = 13751,
    __pg_user_mappings = 13755,
    user_mapping_options = 13761,
    _user_mapping_options = 13760,
    user_mappings = 13766,
    _user_mappings = 13765,
    tweets7 = 16973,
    _tweets7 = 16972,
    tweets = 17009,
    _tweets = 17008,
    testtb = 17014,
    _testtb = 17013,
    cars = 25231,
    _cars = 25230,
    p = 25261,
    _p = 25260,
    people = 25415,
    _people = 25414,
    friend = 25420,
    _friend = 25419,
};
