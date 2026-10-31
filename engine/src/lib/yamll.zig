pub const scalar = @import("yamll/scalar.zig");
pub const scan = @import("yamll/scan.zig");

const emit = @import("yamll/emit.zig");
const parse = @import("yamll/parse.zig");
const fields = @import("yamll/fields.zig");

pub const Emitter = emit.Emitter;
pub const EmitError = emit.Error;

pub const Parser = parse.Parser;
pub const Node = parse.Node;
pub const Kind = parse.Kind;
pub const Error = parse.Error;

pub const Fields = fields.Fields;
pub const Field = fields.Field;
pub const Scalar = fields.Scalar;

test {
    _ = scalar;
    _ = scan;
    _ = emit;
    _ = parse;
    _ = fields;
}
