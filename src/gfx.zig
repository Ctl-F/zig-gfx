const std = @import("std");
pub const sdl = @cImport(@cInclude("SDL3/SDL.h"));
pub const gl = @cImport(@cInclude("glad/glad.h"));

pub const GLVersion = struct {
    major: i32,
    minor: i32,
    core: bool,
};

pub const InitParams = struct {
    title: [*c]const u8,
    width: u32,
    height: u32,
    version: GLVersion,
    vsync_disable: bool = true,
};

// module level constants for simplicity
var window: ?*sdl.SDL_Window = null;
var context: sdl.SDL_GLContext = null;

pub var ShowSDLErrors = false;

pub fn Init(params: InitParams) !void {
    if ((sdl.SDL_WasInit(sdl.SDL_INIT_VIDEO) & sdl.SDL_INIT_VIDEO) == 0) {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            printSDLError();
            return error.SDL_Init;
        }
    }

    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, @intCast(params.version.major));
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, @intCast(params.version.minor));
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, switch (params.version.core) {
        true => sdl.SDL_GL_CONTEXT_PROFILE_CORE,
        false => sdl.SDL_GL_CONTEXT_PROFILE_COMPATIBILITY,
    });

    window = sdl.SDL_CreateWindow(params.title, @intCast(params.width), @intCast(params.height), sdl.SDL_WINDOW_OPENGL);

    if (window == null) {
        printSDLError();
        sdl.SDL_Quit();
        return error.SDL_WindowInit;
    }

    context = sdl.SDL_GL_CreateContext(window);
    if (context == null) {
        printSDLError();
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
        return error.SDL_ContextCreate;
    }

    if (!sdl.SDL_GL_MakeCurrent(window, context)) {
        printSDLError();
        _ = sdl.SDL_GL_DestroyContext(context);
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
        return error.SDL_BindContext;
    }

    if (gl.gladLoadGLLoader(@ptrCast(&sdl.SDL_GL_GetProcAddress)) == 0) {
        _ = sdl.SDL_GL_DestroyContext(context);
        sdl.SDL_DestroyWindow(window);
        sdl.SDL_Quit();
        return error.GLAD_Load;
    }

    if (params.vsync_disable) {
        _ = sdl.SDL_GL_SetSwapInterval(0);
    }

    gl.glViewport(0, 0, @intCast(params.width), @intCast(params.height));
}

pub fn Quit() void {
    _ = sdl.SDL_GL_DestroyContext(context);
    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}

pub fn SwapBuffers() void {
    _ = sdl.SDL_GL_SwapWindow(window);
}

pub fn DebugPrintGLErrors() void {
    if (ShowSDLErrors) {
        const err = gl.glGetError();
        if (err != gl.GL_NO_ERROR) {
            std.debug.print("OpenGL Error: {}\n", .{err});
        }
    } else {
        std.debug.print("Errors are disabled\n", .{});
    }
}

fn printSDLError() void {
    if (ShowSDLErrors) {
        std.debug.print("SDL_Error: {s}\n", .{sdl.SDL_GetError()});
    }
}

pub const VertexType = enum {
    Int1,
    Int2,
    Int3,
    Int4,
    Uint1,
    Uint2,
    Uint3,
    Uint4,
    Float1,
    Float2,
    Float3,
    Float4,
    Double1,
    Double2,
    Double3,
    Double4,

    fn get_count(self: VertexType) u32 {
        return switch (self) {
            .Int1, .Uint1, .Float1, .Double1 => 1,
            .Int2, .Uint2, .Float2, .Double2 => 2,
            .Int3, .Uint3, .Float3, .Double3 => 3,
            .Int4, .Uint4, .Float4, .Double4 => 4,
        };
    }

    fn get_size_single(self: VertexType) u32 {
        return switch (self) {
            .Int1, .Int2, .Int3, .Int4 => @sizeOf(i32),
            .Uint1, .Uint2, .Uint3, .Uint4 => @sizeOf(u32),
            .Float1, .Float2, .Float3, .Float4 => @sizeOf(f32),
            .Double1, .Double2, .Double3, .Double4 => @sizeOf(f64),
        };
    }

    fn get_gl_type(self: VertexType) c_int {
        return switch (self) {
            .Int1, .Int2, .Int3, .Int4 => gl.GL_INT,
            .Uint1, .Uint2, .Uint3, .Uint4 => gl.GL_UNSIGNED_INT,
            .Float1, .Float2, .Float3, .Float4 => gl.GL_FLOAT,
            .Double1, .Double2, .Double3, .Double4 => gl.GL_DOUBLE,
        };
    }

    fn get_size_bytes(self: VertexType) u32 {
        return self.get_size_single() * self.get_count();
    }
};

pub const MAX_VERTEX_ATTRIBUTES = 16;

pub const Primitive = enum {
    Points,
    Lines,
    LineStrip,
    Triangles,
    TriangleStrip,

    fn get_gl_type(self: Primitive) gl.GLenum {
        return switch (self) {
            .Points => gl.GL_POINTS,
            .Lines => gl.GL_LINES,
            .LineStrip => gl.GL_LINE_STRIP,
            .Triangles => gl.GL_TRIANGLES,
            .TriangleStrip => gl.GL_TRIANGLE_STRIP,
        };
    }
};

pub const Mesh = struct {
    vao: u32 = 0,
    buffers: [2]u32 = .{ 0, 0 },
    index_count: u32 = 0,

    pub fn init() Mesh {
        var mesh = Mesh{};

        gl.glGenVertexArrays(1, @ptrCast(&mesh.vao));
        gl.glGenBuffers(2, @ptrCast(&mesh.buffers[0]));

        return mesh;
    }

    pub fn bind(self: Mesh) void {
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.buffers[0]);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.buffers[1]);
    }

    pub fn unbind() void {
        gl.glBindVertexArray(0);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, 0);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    pub fn upload(self: *Mesh, vertices: []const f32, indices: []const u32, format: VertexFormatBuffer) !void {
        self.bind();
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(vertices.len * @sizeOf(f32)), @ptrCast(vertices.ptr), gl.GL_STATIC_DRAW);
        gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @intCast(indices.len * @sizeOf(u32)), @ptrCast(indices.ptr), gl.GL_STATIC_DRAW);
        format.bind();

        self.index_count = @intCast(indices.len);
    }

    pub fn present(self: Mesh, topology: Primitive) void {
        self.bind();
        gl.glDrawElements(topology.get_gl_type(), @intCast(self.index_count), gl.GL_UNSIGNED_INT, null);
    }
};

pub const Shader = struct {
    id: u32,

    pub fn create_from_file(vertex_filename: []const u8, fragment_filename: []const u8) !Shader {
        const allocator = std.heap.page_allocator;
        const vsource = try load_file_text(vertex_filename, allocator);
        defer allocator.free(vsource);

        const fsource = try load_file_text(fragment_filename, allocator);
        defer allocator.free(fsource);

        const vshd = try compile_shader(vsource, gl.GL_VERTEX_SHADER);
        defer gl.glDeleteShader(vshd);

        const fshd = try compile_shader(fsource, gl.GL_FRAGMENT_SHADER);
        defer gl.glDeleteShader(fshd);

        const progId: u32 = gl.glCreateProgram();

        gl.glAttachShader(progId, vshd);
        defer gl.glDetachShader(progId, vshd);

        gl.glAttachShader(progId, fshd);
        defer gl.glDetachShader(progId, fshd);

        gl.glLinkProgram(progId);
        var success: c_int = 0;

        gl.glGetProgramiv(progId, gl.GL_LINK_STATUS, &success);
        if (progId == gl.GL_FALSE) {
            defer gl.glDeleteProgram(progId);
            var info_log = [_]u8{0} ** 1024;

            gl.glGetProgramInfoLog(progId, info_log.len, null, @ptrCast(&info_log));
            std.debug.print("Program Link Error: {s}\n", .{info_log});
            return error.ProgramLinkerError;
        }

        return Shader{ .id = @intCast(progId) };
    }

    pub fn destroy(self: Shader) void {
        gl.glDeleteProgram(self.id);
    }

    fn load_file_text(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
        const oBuffer = try std.fs.cwd().readFileAlloc(allocator, filename, std.math.maxInt(usize));
        const nBuffer = try allocator.alloc(u8, oBuffer.len + 1);
        @memcpy(nBuffer[0..oBuffer.len], oBuffer);
        nBuffer[oBuffer.len] = 0;
        allocator.free(oBuffer);
        return nBuffer;
    }

    fn compile_shader(shader_source: []const u8, shader_stage: gl.GLenum) !u32 {
        const shader_id: u32 = gl.glCreateShader(shader_stage);

        gl.glShaderSource(shader_id, 1, @ptrCast(&shader_source), null);
        gl.glCompileShader(shader_id);

        var success: c_int = 0;
        gl.glGetShaderiv(shader_id, gl.GL_COMPILE_STATUS, &success);
        if (success == gl.GL_FALSE) {
            var info_log = [_]u8{0} ** 1024;
            gl.glGetShaderInfoLog(shader_id, info_log.len, null, @ptrCast(&info_log));
            std.debug.print("Shader Compiler Error: {s}\n", .{info_log});
            return error.ShaderCompileError;
        }
        return shader_id;
    }

    pub fn bind(self: Shader) void {
        gl.glUseProgram(self.id);
    }

    pub fn unbind() void {
        gl.glUseProgram(0);
    }
};

pub fn set_uniform(comptime ty: type, location: i32, value: ty) void {
    switch (@typeInfo(ty)) {
        .Int => gl.glUniform1i(location, value),
        .Float => gl.glUniform1f(location, value),
        .Struct => |s| {
            if (@TypeOf(value) == mat4) {
                gl.glUniformMatrix4fv(location, 1, gl.GL_FALSE, &value.data[0]);
            } else if (s.fields.len == 2) {
                gl.glUniform2f(location, value[0], value[1]);
            } else if (s.fields.len == 3) {
                gl.glUniform3f(location, value[0], value[1], value[2]);
            } else if (s.fields.len == 4) {
                gl.glUniform4f(location, value[0], value[1], value[2], value[3]);
            } else {
                @compileError("Unsuppored struct type for uniforms.");
            }
        },
        else => @compileError("Unsupported uniform type"),
    }
}

pub const VertexAttribute = struct {
    vertex_type: VertexType,
    offset: u32,
};

pub const VertexFormatBuffer = struct {
    attributes: [MAX_VERTEX_ATTRIBUTES]VertexAttribute = undefined,
    attribute_count: u32 = 0,
    stride: u32 = 0,
    next_offset: u32 = 0,

    pub fn add_attribute(self: *VertexFormatBuffer, attrib: VertexType) !void {
        if (self.attribute_count >= MAX_VERTEX_ATTRIBUTES) {
            return error.TooManyAttributes;
        }
        self.attributes[self.attribute_count] = VertexAttribute{ .vertex_type = attrib, .offset = self.next_offset };
        self.next_offset += attrib.get_size_bytes();
        self.stride += attrib.get_size_bytes();
        self.attribute_count += 1;
    }

    pub fn bind(self: VertexFormatBuffer) void {
        var i: u32 = 0;
        while (i < self.attribute_count) : (i += 1) {
            gl.glEnableVertexAttribArray(i);
            gl.glVertexAttribPointer(i, @intCast(self.attributes[i].vertex_type.get_count()), @intCast(self.attributes[i].vertex_type.get_gl_type()), gl.GL_FALSE, @intCast(self.stride), @ptrFromInt(self.attributes[i].offset));
        }
    }
};

pub const mat4 = struct {
    data: [16]f32,

    pub fn identity() mat4 {
        return mat4{
            .data = [_]f32{
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            },
        };
    }

    pub fn translation(x: f32, y: f32, z: f32) mat4 {
        return mat4{
            1, 0, 0, x,
            0, 1, 0, y,
            0, 0, 1, z,
            0, 0, 0, 1,
        };
    }

    pub fn perspective(fov: f32, aspect: f32, near: f32, far: f32) mat4 {
        const tan_half_fov = @tan(fov / 2);
        return mat4{ .data = [_]f32{
            1 / (aspect * tan_half_fov), 0,                0,                            0,
            0,                           1 / tan_half_fov, 0,                            0,
            0,                           0,                -(far + near) / (far - near), -(2 * far * near) / (far - near),
            0,                           0,                -1,                           0,
        } };
    }

    pub fn multiply(self: mat4, other: mat4) mat4 {
        var result: mat4 = undefined;
        for (0..4) |row| {
            for (0..4) |col| {
                result.data[row + col * 4] =
                    self.data[row + 0 * 4] * other.data[0 + col * 4] +
                    self.data[row + 1 * 4] * other.data[1 + col * 4] +
                    self.data[row + 2 * 4] * other.data[2 + col * 4] +
                    self.data[row + 3 * 4] * other.data[3 + col * 4];
            }
        }
        return result;
    }
};
