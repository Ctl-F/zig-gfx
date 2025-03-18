/// BASIC LINEAR ALGEBRA LIBRARY
/// This is not an all-inclusive library
/// and is mostly to cover the basics needed
/// for simple 3d game math.
/// We are "borrowing" the mat4 implementation
/// from zlm. This library also isn't heavily optimized
/// beyond using SIMD operations where convenient.
const std = @import("std");

pub const vec2 = @Vector(2, f32);
pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);

pub fn dot(a: anytype, b: @TypeOf(a)) f32 {
    comptime {
        if (@typeInfo(@TypeOf(a)) != .vector) {
            @compileError("dot() function requires vector types.");
        }
    }
    return @reduce(.Add, a * b);
}

pub fn cross(a: vec3, b: vec3) vec3 {
    return vec3{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

pub fn normalize(a: anytype) @TypeOf(a) {
    comptime {
        if (@typeInfo(@TypeOf(a)) != .vector) {
            @compileError("normalize() function requires vector type.");
        }
    }

    const len = @sqrt(dot(a, a));

    if (len == 0.0) {
        return @splat(0.0);
    }

    const divisor: @TypeOf(a) = @splat(1.0 / len);
    return a * divisor;
}

/// 4 by 4 matrix type.
pub const mat4 = extern struct {
    pub const Self = @This();
    fields: [4][4]f32, // [row][col]

    /// zero matrix.
    pub const zero = Self{
        .fields = [4][4]f32{
            [4]f32{ 0, 0, 0, 0 },
            [4]f32{ 0, 0, 0, 0 },
            [4]f32{ 0, 0, 0, 0 },
            [4]f32{ 0, 0, 0, 0 },
        },
    };

    /// identitiy matrix
    pub const identity = Self{
        .fields = [4][4]f32{
            [4]f32{ 1, 0, 0, 0 },
            [4]f32{ 0, 1, 0, 0 },
            [4]f32{ 0, 0, 1, 0 },
            [4]f32{ 0, 0, 0, 1 },
        },
    };

    pub fn format(value: Self, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        try stream.writeAll("mat4{");

        inline for (0..4) |i| {
            const row = value.fields[i];
            try stream.print(" ({d:.2} {d:.2} {d:.2} {d:.2})", .{ row[0], row[1], row[2], row[3] });
        }

        try stream.writeAll(" }");
    }

    /// performs matrix multiplication of a*b
    pub fn mul(a: Self, b: Self) Self {
        var result: Self = undefined;
        inline for (0..4) |row| {
            inline for (0..4) |col| {
                var sum: f32 = 0.0;
                inline for (0..4) |i| {
                    sum += a.fields[row][i] * b.fields[i][col];
                }
                result.fields[row][col] = sum;
            }
        }
        return result;
    }

    /// transposes the matrix.
    /// this will swap columns with rows.
    pub fn transpose(a: Self) Self {
        var result: Self = undefined;
        inline for (0..4) |row| {
            inline for (0..4) |col| {
                result.fields[row][col] = a.fields[col][row];
            }
        }
        return result;
    }

    // taken from GLM implementation

    /// Creates a look-at matrix.
    /// The matrix will create a transformation that can be used
    /// as a camera transform.
    /// the camera is located at `eye` and will look into `direction`.
    /// `up` is the direction from the screen center to the upper screen border.
    pub fn createLook(eye: vec3, direction: vec3, up: vec3) Self {
        const f = normalize(direction);
        const s = normalize(cross(f, up));
        const u = cross(s, f);

        var result = Self.identity;
        result.fields[0][0] = s[0];
        result.fields[1][0] = s[1];
        result.fields[2][0] = s[2];
        result.fields[0][1] = u[0];
        result.fields[1][1] = u[1];
        result.fields[2][1] = u[2];
        result.fields[0][2] = -f[0];
        result.fields[1][2] = -f[1];
        result.fields[2][2] = -f[2];
        result.fields[3][0] = -dot(s, eye);
        result.fields[3][1] = -dot(u, eye);
        result.fields[3][2] = dot(f, eye);
        return result;
    }

    /// Creates a look-at matrix.
    /// The matrix will create a transformation that can be used
    /// as a camera transform.
    /// the camera is located at `eye` and will look at `center`.
    /// `up` is the direction from the screen center to the upper screen border.
    pub fn createLookAt(eye: vec3, center: vec3, up: vec3) Self {
        return createLook(eye, center - eye, up);
    }

    // taken from GLM implementation

    /// creates a perspective transformation matrix.
    /// `fov` is the field of view in radians,
    /// `aspect` is the screen aspect ratio (width / height)
    /// `near` is the distance of the near clip plane, whereas `far` is the distance to the far clip plane.
    pub fn createPerspective(fov: f32, aspect: f32, near: f32, far: f32) Self {
        std.debug.assert(@abs(aspect - 0.001) > 0);

        const tanHalfFovy = @tan(fov / 2);

        var result = Self.zero;
        result.fields[0][0] = 1.0 / (aspect * tanHalfFovy);
        result.fields[1][1] = 1.0 / (tanHalfFovy);
        result.fields[2][2] = -(far + near) / (far - near);
        result.fields[2][3] = -1;
        result.fields[3][2] = -(2 * far * near) / (far - near);
        return result;
    }

    /// creates a rotation matrix around a certain axis.
    pub fn createAngleAxis(axis: vec3, angle: f32) Self {
        const cos = @cos(angle);
        const sin = @sin(angle);

        const normalized = normalize(axis);
        const x = normalized.x;
        const y = normalized.y;
        const z = normalized.z;

        return Self{
            .fields = [4][4]f32{
                [4]f32{ cos + x * x * (1 - cos), x * y * (1 - cos) + z * sin, x * z * (1 - cos) - y * sin, 0 },
                [4]f32{ y * x * (1 - cos) - z * sin, cos + y * y * (1 - cos), y * z * (1 - cos) + x * sin, 0 },
                [4]f32{ z * x * (1 - cos) + y * sin, z * y * (1 - cos) - x * sin, cos + z * z * (1 - cos), 0 },
                [4]f32{ 0, 0, 0, 1 },
            },
        };
    }

    /// creates matrix that will scale a homogeneous matrix.
    pub fn createUniformScale(scale: f32) Self {
        return createScale(scale, scale, scale);
    }

    /// Creates a non-uniform scaling matrix
    pub fn createScale(x: f32, y: f32, z: f32) Self {
        return Self{
            .fields = [4][4]f32{
                [4]f32{ x, 0, 0, 0 },
                [4]f32{ 0, y, 0, 0 },
                [4]f32{ 0, 0, z, 0 },
                [4]f32{ 0, 0, 0, 1 },
            },
        };
    }

    /// creates matrix that will translate a homogeneous matrix.
    pub fn createTranslationXYZ(x: f32, y: f32, z: f32) Self {
        return Self{
            .fields = [4][4]f32{
                [4]f32{ 1, 0, 0, 0 },
                [4]f32{ 0, 1, 0, 0 },
                [4]f32{ 0, 0, 1, 0 },
                [4]f32{ x, y, z, 1 },
            },
        };
    }

    /// creates matrix that will scale a homogeneous matrix.
    pub fn createTranslation(v: vec3) Self {
        return Self{
            .fields = [4][4]f32{
                [4]f32{ 1, 0, 0, 0 },
                [4]f32{ 0, 1, 0, 0 },
                [4]f32{ 0, 0, 1, 0 },
                [4]f32{ v.x, v.y, v.z, 1 },
            },
        };
    }

    /// creates an orthogonal projection matrix.
    /// `left`, `right`, `bottom` and `top` are the borders of the screen whereas `near` and `far` define the
    /// distance of the near and far clipping planes.
    pub fn createOrthogonal(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Self {
        var result = Self.identity;
        result.fields[0][0] = 2 / (right - left);
        result.fields[1][1] = 2 / (top - bottom);
        result.fields[2][2] = -2 / (far - near);
        result.fields[3][0] = -(right + left) / (right - left);
        result.fields[3][1] = -(top + bottom) / (top - bottom);
        result.fields[3][2] = -(far + near) / (far - near);
        return result;
    }

    /// Batch matrix multiplication. Will multiply all matrices from "first" to "last".
    pub fn batchMul(items: []const Self) Self {
        if (items.len == 0)
            return Self.identity;
        if (items.len == 1)
            return items[0];
        var value = items[0];
        for (1..items.len) |i| {
            value = value.mul(items[i]);
        }
        return value;
    }

    /// calculates the invert matrix when it's possible (returns null otherwise)
    /// only works on float matrices
    pub fn invert(src: Self) ?Self {
        // https://github.com/stackgl/gl-mat4/blob/master/invert.js
        const a: [16]f32 = @bitCast(src.fields);

        const a00 = a[0];
        const a01 = a[1];
        const a02 = a[2];
        const a03 = a[3];
        const a10 = a[4];
        const a11 = a[5];
        const a12 = a[6];
        const a13 = a[7];
        const a20 = a[8];
        const a21 = a[9];
        const a22 = a[10];
        const a23 = a[11];
        const a30 = a[12];
        const a31 = a[13];
        const a32 = a[14];
        const a33 = a[15];

        const b00 = a00 * a11 - a01 * a10;
        const b01 = a00 * a12 - a02 * a10;
        const b02 = a00 * a13 - a03 * a10;
        const b03 = a01 * a12 - a02 * a11;
        const b04 = a01 * a13 - a03 * a11;
        const b05 = a02 * a13 - a03 * a12;
        const b06 = a20 * a31 - a21 * a30;
        const b07 = a20 * a32 - a22 * a30;
        const b08 = a20 * a33 - a23 * a30;
        const b09 = a21 * a32 - a22 * a31;
        const b10 = a21 * a33 - a23 * a31;
        const b11 = a22 * a33 - a23 * a32;

        // Calculate the determinant
        var det = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;

        if (std.math.approxEqAbs(f32, det, 0, 1e-8)) {
            return null;
        }
        det = 1.0 / det;

        const out = [16]f32{
            (a11 * b11 - a12 * b10 + a13 * b09) * det, // 0
            (a02 * b10 - a01 * b11 - a03 * b09) * det, // 1
            (a31 * b05 - a32 * b04 + a33 * b03) * det, // 2
            (a22 * b04 - a21 * b05 - a23 * b03) * det, // 3
            (a12 * b08 - a10 * b11 - a13 * b07) * det, // 4
            (a00 * b11 - a02 * b08 + a03 * b07) * det, // 5
            (a32 * b02 - a30 * b05 - a33 * b01) * det, // 6
            (a20 * b05 - a22 * b02 + a23 * b01) * det, // 7
            (a10 * b10 - a11 * b08 + a13 * b06) * det, // 8
            (a01 * b08 - a00 * b10 - a03 * b06) * det, // 9
            (a30 * b04 - a31 * b02 + a33 * b00) * det, // 10
            (a21 * b02 - a20 * b04 - a23 * b00) * det, // 11
            (a11 * b07 - a10 * b09 - a12 * b06) * det, // 12
            (a00 * b09 - a01 * b07 + a02 * b06) * det, // 13
            (a31 * b01 - a30 * b03 - a32 * b00) * det, // 14
            (a20 * b03 - a21 * b01 + a22 * b00) * det, // 15
        };
        return Self{
            .fields = @as([4][4]f32, @bitCast(out)),
        };
    }
};

pub const quat = struct {
    pub const Self = @This();
    intern: vec4,

    pub inline fn init(x: f32, y: f32, z: f32, w: f32) Self {
        return Self{ .intern = vec4{ x, y, z, w } };
    }

    pub inline fn mul(a: Self, b: Self) Self {
        const ax, const ay, const az, const aw = a.intern;
        const bx, const by, const bz, const bw = b.intern;

        return Self.init(aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz);
    }

    pub inline fn normalize(q: Self) Self {
        const len_sq = dot(q.intern, q.intern);

        if (len_sq == 0) {
            return Self.identity;
        }
        const divisor: vec4 = @splat(1.0 / @sqrt(len_sq));
        return Self{ .intern = q.intern * divisor };
    }

    pub inline fn conjugate(q: Self) Self {
        return Self.init(-q.intern[0], -q.intern[1], -q.intern[2], q.intern[3]);
    }

    pub inline fn to_mat4(q: Self) mat4 {
        const x2, const y2, const z2, _ = q.intern * q.intern;
        const xy = q.intern[0] * q.intern[1];
        const xz = q.intern[0] * q.intern[2];
        const yz = q.intern[1] * q.intern[2];
        const wx = q.intern[3] * q.intern[0];
        const wy = q.intern[3] * q.intern[1];
        const wz = q.intern[3] * q.intern[2];

        const out = [_]f32{
            1.0 - 2.0 * (y2 + z2), 2.0 * (xy - wz),       2.0 * (xz + wy),       0.0,
            2.0 * (xy + wz),       1.0 - 2.0 * (x2 + z2), 2.0 * (yz - wx),       0.0,
            2.0 * (xz - wy),       2.0 * (yz + wx),       1.0 - 2.0 * (x2 + y2), 0.0,
            0.0,                   0.0,                   0.0,                   1.0,
        };
        return mat4{
            .fields = @as([4][4]f32, @bitCast(out)),
        };
    }

    pub inline fn rotate_vec3(q: Self, v: vec3) vec3 {
        const qx, const qy, const qz, const qw = q.intern;
        const qv = vec3{ qx, qy, qz };

        const twovec: vec3 = @splat(2.0);
        const t = twovec * cross(qv, v);
        const vqw: vec3 = @splat(qw);

        return v + (vqw * t) + cross(qv, t);
    }

    pub inline fn lerp(a: Self, b: Self, t: f32) Self {
        std.debug.assert(0.0 <= t and t <= 1.0);

        const inv_t: vec4 = @splat(1.0 - t);
        const t_v: vec4 = @splat(t);

        const blended = Self{
            .intern = a.intern * inv_t + b.intern * t_v,
        };
        return blended.normalize();
    }

    pub inline fn slerp(a: Self, b: Self, t: f32) Self {
        std.debug.assert(0.0 <= t and t <= 1.0);

        const q1 = a;
        var q2 = b;

        var abdot = dot(q1.intern, q2.intern);

        if (abdot < 0.0) {
            q2.intern *= @splat(-1);
            abdot = -abdot;
        }

        if (abdot > (1.0 - std.math.floatEps(f32))) {
            return lerp(q1, q2, t);
        }

        const theta = std.math.acos(abdot);
        const sin_theta = @sin(theta);

        const w1: vec4 = @splat(@sin((1.0 - t) * theta) / sin_theta);
        const w2: vec4 = @splat(@sin(t * theta) / sin_theta);

        return Self{ .intern = (q1.intern * w1) + (q2.intern * w2) };
    }

    pub inline fn angle_axis(angle: f32, axis: vec3) Self {
        const half_angle = angle * 0.5;
        const s: vec3 = @splat(@sin(half_angle));
        const c = @cos(half_angle);
        const xx, const yy, const zz = (axis * s);

        return Self{ .intern = vec4{ xx, yy, zz, c } };
    }

    pub const identity = Self.init(0.0, 0.0, 0.0, 1.0);
};
