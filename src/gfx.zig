/// GFX is a simple wrapper around SDL3 and opengl. We have bundled glad and it was generated to support opengl 3.3 core.
/// If a different verion of opengl is desired you will probably want to regenrate glad to reflect that.
/// Simple example of a basic program that should be enough to get you started:
///
/// <Example.zig>
///
/// const std = @import("std");
/// const gfx = @import("gfx.zig");
///
/// // if you want to use sdl/opengl directly you can
/// // by accessing them via gfx.sdl and gfx.gl
/// // or by re-exposing them to your module directly:
/// // const sdl = gfx.sdl;
/// // const gl = gfx.gl;
///
///  // setup for input:
///  // the errors that your program might raise during event handling
///  const MyErrors = error{ NullContext }; // add any errors to this set as needed
///
///  // a struct to give your event handling some context to operate on. The type is needed
///  // though the actual context itself is technically optional
///  const MyContext = struct {
///     running: bool,
///  };
///
///  const EventHooks = gfx.CreateEventHooks(MyContext, MyErrors);
///  const EventHooksType = EventHooks.EventHooks;
///
///  // the minimal event handler for the "onQuit" event (when the close button is clicked)
///  fn handleOnQuit(_: gfx.EventType, context: ?*MyContext) MyErrors!void {
///     if(context) |ctx| {
///         ctx.running = false;
///         return;
///     }
///
///     return MyErrors.NullContext;
///   }
///
///
/// pub fn main() !void {
///     // if you want to show sdl errors when they happen
///     // set this to true, otherwise keep it at false
///     // gfx.ShowSDLErrors = true;
///
///     // window settings and context version
///     const windowParams = gfx.InitParams {
///         .title = "SDL Window in Zig",
///         .width = 1280,
///         .height = 720,
///         .version = gfx.GLVersion{ .major = 3, .minor = 3, .core = true },
///     };
///
///     // initialize sdl and create a window
///     try gfx.Init(params);
///     defer gfx.Quit();
///
///     /// setup the vertex format for the buffer
///     var vertex_format = gfx.VertexFormatBuffer{};
///     try vertex_format.add_attribute(gfx.VertexType.Float3); // position: vec3
///     try vertex_format.add_attribute(gfx.VertexType.Float3); // color: vec3
///
///     const vertices = [_]f32 {
///     //   x,    y,    z,    r,  g,  b,
///        0.0, -0.5,  0.0,   1.0, 0.0, 0.0,
///       -0.5,  0.5,  0.0,   0.0, 1.0, 0.0,
///        0.5,  0.5,  0.0,   0.0, 0.0, 1.0,
///     };
///     const indices = [_]u32 {
///         0, 1, 2,
///     };
///
///     // upload the vertex information to the gpu using our vertex format
///     var mesh = gfx.Mesh.init();
///     try mesh.upload(&vertices, &indices, vertex_format);
///     defer mesh.destroy();
///
///     // create our shader from file.
///     const shader = try gfx.Shader.create_from_file("vertex.glsl", "fragment.glsl", std.heap.page_allocator);
///     defer shader.destroy();
///
///     var appContext = MyContext{ .running = true };
///     const eventHooks = EventHooksType {
///         .on_quit = handleOnQuit,
///     };
///
///
///     // main loop
///     main_loop: while(true){
///         try EventHooks.PollEvents(eventHooks, &appContext);
///
///         // will be refactored to not require direct usage of opengl
///         gfx.gl.glClearColor(0.0, 0.0, 0.01, 1.0);
///         gfx.gl.glClear(gfx.gl.GL_COLOR_BUFFER_BIT);
///
///         shader.bind();
///         mesh.present(gfx.Primitive.Triangles);
///
///         gfx.SwapBuffers();
///     }
/// }
/// </Example.zig>
const std = @import("std");
pub const sdl = @cImport(@cInclude("SDL3/SDL.h"));
pub const gl = @cImport(@cInclude("glad/glad.h"));
pub const ttf = @cImport(@cInclude("stb_truetype.h"));
pub const pck = @cImport(@cInclude("stb_rect_pack.h"));
pub const img = @cImport(@cInclude("stb_image.h"));

pub const vmath = @import("vmath.zig");

const vec2 = vmath.vec2;
const vec3 = vmath.vec3;
const vec4 = vmath.vec4;
const mat4 = vmath.mat4;
const quat = vmath.quat;

/// Represents a version of OpenGL (core = false for compatability profile)
pub const GLVersion = struct {
    major: i32,
    minor: i32,
    core: bool,
};

/// Represents window parameters and opengl version for
/// initialization
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

/// initialize sdl and create a window using the initialize parameters
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

/// destroy the window and quit sdl
pub fn Quit() void {
    _ = sdl.SDL_GL_DestroyContext(context);
    sdl.SDL_DestroyWindow(window);
    sdl.SDL_Quit();
}

/// present the opengl render to the screen
pub fn SwapBuffers() void {
    _ = sdl.SDL_GL_SwapWindow(window);
}

/// display any opengl errors (if they have occurred)
pub fn DebugPrintGLErrors() void {
    if (ShowSDLErrors) {
        const err = gl.glGetError();
        if (err != gl.GL_NO_ERROR) {
            std.debug.print("OpenGL Error: {}\n", .{err});
        }
    }
}

/// helper function to display sdl errors (if any have occurred);
fn printSDLError() void {
    if (ShowSDLErrors) {
        std.debug.print("SDL_Error: {s}\n", .{sdl.SDL_GetError()});
    }
}

pub const TexturePolicy = enum {
    Repeat,
    Clamp,
    Mirrored,

    pub fn get_gl_policy(self: TexturePolicy) c_int {
        return switch (self) {
            .Repeat => gl.GL_REPEAT,
            .Mirrored => gl.GL_MIRRORED_REPEAT,
            .Clamp => gl.GL_CLAMP_TO_EDGE,
        };
    }
};

pub const TextureFormat = enum {
    RGBA, // default for 99% of textures
    Mono, // specifically for font atlases (allocated as monochrome bitmaps)
};

pub const SamplePolicy = enum {
    Nearest,
    NearestMipNearest,
    NearestMipLinear,
    Linear,
    LinearMipNearest,
    LinearMipLinear,

    pub fn get_gl_policy(self: SamplePolicy) c_int {
        return switch (self) {
            .Nearest => gl.GL_NEAREST,
            .NearestMipNearest => gl.GL_NEAREST_MIPMAP_NEAREST,
            .NearestMipLinear => gl.GL_NEAREST_MIPMAP_LINEAR,
            .Linear => gl.GL_LINEAR,
            .LinearMipNearest => gl.GL_LINEAR_MIPMAP_NEAREST,
            .LinearMipLinear => gl.GL_LINEAR_MIPMAP_LINEAR,
        };
    }
};

pub const TextureSettings = struct {
    texture_policy: TexturePolicy,
    min_sample_policy: SamplePolicy,
    mag_sample_policy: SamplePolicy,
    gen_mipmaps: bool = true,
    format: TextureFormat = TextureFormat.RGBA,
};

pub const Texture = struct {
    id: u32,
    settings: TextureSettings,

    pub inline fn bind_to_slot(self: Texture, slot: u32) void {
        const cslot = gl.GL_TEXTURE0 + @as(c_int, @intCast(slot));
        gl.glActiveTexture(@as(gl.GLenum, @intCast(cslot)));
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.id);
    }
};

pub const Image = ?*sdl.SDL_Surface;

pub fn UploadImage(image: Image, settings: TextureSettings) !Texture {
    return UploadImagePixels(image.?.pixels, @intCast(image.?.w), @intCast(image.?.h), settings);
}

pub fn UploadImagePixels(pixels: ?*anyopaque, width: u32, height: u32, settings: TextureSettings) !Texture {
    var texture: Texture = Texture{ .id = 0, .settings = settings };

    gl.glGenTextures(1, &texture.id);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture.id);

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, settings.min_sample_policy.get_gl_policy());
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, settings.mag_sample_policy.get_gl_policy());
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, settings.texture_policy.get_gl_policy());
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, settings.texture_policy.get_gl_policy());

    const iFmt, const eFmt = switch (settings.format) {
        .Mono => .{ gl.GL_RED, gl.GL_RED },
        .RGBA => .{ gl.GL_RGBA8, gl.GL_BGRA },
    };

    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, @intCast(iFmt), @intCast(width), @intCast(height), 0, @intCast(eFmt), gl.GL_UNSIGNED_BYTE, pixels);

    if (settings.gen_mipmaps) {
        gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
    }

    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);

    return texture;
}

pub fn DestroyTexture(texture: Texture) void {
    gl.glDeleteTextures(1, texture.id);
}

pub fn LoadImage(filename: [*c]const u8) !Image {
    var x: c_int = 0;
    var y: c_int = 0;
    var ch: c_int = 0;

    const image = img.stbi_load(filename, &x, &y, &ch, 4);

    if (image == null) {
        if (ShowSDLErrors) {
            std.debug.print("Failed to load image `{s}`: {s}.\n", .{ filename, img.stbi_failure_reason() });
        }
        return error.ImageLoad;
    }
    defer img.stbi_image_free(image);

    const stagingImage: Image = sdl.SDL_CreateSurfaceFrom(x, y, sdl.SDL_PIXELFORMAT_RGBA32, image, x * 4);
    if (stagingImage == null) {
        printSDLError();
        return error.StagingBufferFailure;
    }
    defer sdl.SDL_DestroySurface(stagingImage);

    const finalImage = sdl.SDL_ConvertSurface(stagingImage, sdl.SDL_PIXELFORMAT_BGRA32);

    if (finalImage == null) {
        printSDLError();
        return error.ImageBufferAllocation;
    }

    return finalImage;
}
pub fn DestroyImage(image: Image) void {
    if (image != null) {
        sdl.SDL_DestroySurface(image);
    }
}

/// types of data that can exist in a vertex format.
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

/// maximum number of vertex attributes a format can have (increase this if 16 is too few somehow)
pub const MAX_VERTEX_ATTRIBUTES = 16;

/// primitive type for render. The most common is Trianges
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

/// bundles vertex buffer, index buffer and array object together for presentation.
pub const Mesh = struct {
    vao: u32 = 0,
    buffers: [2]u32 = .{ 0, 0 },
    index_count: u32 = 0,

    /// create a new vertex array and allocate opengl buffers
    pub fn init() Mesh {
        var mesh = Mesh{};

        gl.glGenVertexArrays(1, @ptrCast(&mesh.vao));
        gl.glGenBuffers(2, @ptrCast(&mesh.buffers[0]));

        return mesh;
    }

    /// release the buffers and array object
    pub fn destroy(self: Mesh) void {
        Mesh.unbind();
        gl.glDeleteBuffers(2, &self.buffers[0]);
        gl.glDeleteVertexArrays(1, &self.vao);
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

    /// present the mesh to opengl for rendering.
    /// you must have already bound whatever shader you will be using and have uploaded any
    /// uniform data before calling this.
    pub fn present(self: Mesh, topology: Primitive) void {
        self.bind();
        gl.glDrawElements(topology.get_gl_type(), @intCast(self.index_count), gl.GL_UNSIGNED_INT, null);
    }
};

pub const Shader = struct {
    id: u32,

    pub fn create_from_source(vertex_source: []const u8, fragment_source: []const u8) !Shader {
        const vshd = try compile_shader(vertex_source, gl.GL_VERTEX_SHADER);
        defer gl.glDeleteShader(vshd);

        const fshd = try compile_shader(fragment_source, gl.GL_FRAGMENT_SHADER);
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

    pub fn create_from_file(vertex_filename: []const u8, fragment_filename: []const u8, allocator: std.mem.Allocator) !Shader {
        const vsource = try load_file_text(vertex_filename, allocator);
        defer allocator.free(vsource);

        const fsource = try load_file_text(fragment_filename, allocator);
        defer allocator.free(fsource);

        return create_from_source(vsource, fsource);
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

pub const VertexAttribute = struct {
    vertex_type: VertexType,
    offset: u32,
};

/// represents the format that the vertex buffer will follow. This effectively tracks the total size
/// a single vertex takes along with where each attribute begins and it's type.
/// for a more complete vertex:
/// const Vertex = struct {
///     x: f32,
///     y: f32,
///     z: f32,
///     normal_x: f32,
///     normal_y: f32,
///     normal_z: f32,
///     uv_x: f32,
///     uv_y: f32,
///     color_r: f32,
///     color_g: f32,
///     color_b: f32,
/// };
///
/// You would build the vertex format like so:
/// var vfmt = VertexFormatBuffer{};
/// try vfmt.add_attribute(VertexType.Float3);
/// try vfmt.add_attribute(VertexType.Float3);
/// try vfmt.add_attribute(VertexType.Float2);
/// try vfmt.add_attribute(VertexType.Float3);
///
/// note that this should only really fail if you add too many vertex attributes to a single VertexFormatBuffer.
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

pub fn get_uniform_location(shader: Shader, name: [*c]const u8) i32 {
    return gl.glGetUniformLocation(shader.id, @ptrCast(name));
}

pub fn set_uniform(location: i32, value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        std.builtin.Type.int => gl.glUniform1i(location, value),
        std.builtin.Type.float => gl.glUniform1f(location, value),
        std.builtin.Type.@"struct" => |s| {
            if (@TypeOf(value) == mat4) {
                gl.glUniformMatrix4fv(location, 1, gl.GL_FALSE, &value.fields[0]);
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

pub fn set_uniform_texture(location: i32, slot: u32, tex: Texture) void {
    gl.glUniform1i(location, @intCast(slot));
    tex.bind_to_slot(slot);
}

pub const EventTy = sdl.SDL_Event;

pub const FontAtlasConfig = struct {
    width: u32 = 512,
    height: u32 = 512,
    font_size: f32 = 32.0,
    begin_char: u8 = ' ',
    end_char: u8 = '~',
    oversample: u32 = 2,
};

pub const FontBuffer = struct {
    atlas_data: []u8,
    char_data: []ttf.stbtt_packedchar,
    config: FontAtlasConfig,
    /// returns the visual glyph (quad info) for the given character
    /// along with the position of the next character
    pub fn get_glyph(self: FontBuffer, char: u8, loc: vec2) !struct { VisualGlyph, ?vec2 } {
        if (char < self.config.begin_char or char > self.config.end_char) {
            return error.CharOutOfRange;
        }

        var quad: ttf.stbtt_aligned_quad = undefined;
        var cur_x, var cur_y = loc;

        ttf.stbtt_GetPackedQuad(@ptrCast(self.char_data), @intCast(self.config.width), @intCast(self.config.height), @intCast(char - self.config.begin_char), &cur_x, &cur_y, &quad, 1);

        //std.debug.print("{}({d}, {d}) -> ({d}, {d})\n", .{ char, loc[0], loc[1], cur_x, cur_y });

        return .{
            VisualGlyph{
                .top_left = vec2{ quad.x0, quad.y0 },
                .bottom_right = vec2{ quad.x1, quad.y1 },
                .uv0 = vec2{ quad.s0, quad.t0 },
                .uv1 = vec2{ quad.s1, quad.t1 },
            },
            vec2{ cur_x, cur_y },
        };
    }
};

pub const VertexList = std.ArrayList(f32);
pub const IndexList = std.ArrayList(u32);

pub const TextRenderer = struct {
    const DEFAULT_QUAD_COUNT = 100;
    const DEFAULT_VERTEX_ALLOCATION_COUNT = DEFAULT_QUAD_COUNT * 4;
    const DEFAULT_INDEX_ALLOCATION_COUNT = DEFAULT_QUAD_COUNT * 6;

    const Self = @This();

    fontBuffer: FontBuffer,
    vertexFormat: VertexFormatBuffer,
    allocator: std.mem.Allocator,
    vertices: VertexList,
    indices: IndexList,
    textMesh: Mesh,
    fontAtlas: Texture,
    projection_mat: mat4,
    screen_size: vec2,

    pub fn init_with_defaults(allocator: std.mem.Allocator, fontData: []u8, fontConfig: FontAtlasConfig, orthoSize: vec2) !Self {
        var tr: Self = undefined;

        tr.allocator = allocator;
        tr.fontBuffer = try AllocateFontBuffer(allocator, fontConfig);

        PackFontAtlas(fontData, &tr.fontBuffer) catch |err| {
            FreeFontBuffer(allocator, tr.fontBuffer);
            return err;
        };

        tr.vertices = VertexList.init(allocator);

        tr.vertices.ensureTotalCapacity(DEFAULT_VERTEX_ALLOCATION_COUNT) catch |err| {
            FreeFontBuffer(allocator, tr.fontBuffer);
            tr.vertices.deinit();
            return err;
        };

        tr.indices = IndexList.init(allocator);
        tr.indices.ensureTotalCapacity(DEFAULT_INDEX_ALLOCATION_COUNT) catch |err| {
            FreeFontBuffer(allocator, tr.fontBuffer);
            tr.vertices.deinit();
            tr.indices.deinit();
            return err;
        };

        tr.vertexFormat = VertexFormatBuffer{};
        try tr.vertexFormat.add_attribute(VertexType.Float3); // position
        try tr.vertexFormat.add_attribute(VertexType.Float2); // uv
        try tr.vertexFormat.add_attribute(VertexType.Float3); // glyph color

        const textureConfig = TextureSettings{
            .gen_mipmaps = false,
            .mag_sample_policy = SamplePolicy.Nearest,
            .min_sample_policy = SamplePolicy.Nearest,
            .texture_policy = TexturePolicy.Repeat,
            .format = TextureFormat.Mono,
        };
        tr.fontAtlas = UploadImagePixels(tr.fontBuffer.atlas_data.ptr, fontConfig.width, fontConfig.height, textureConfig) catch |err| {
            FreeFontBuffer(allocator, tr.fontBuffer);
            tr.vertices.deinit();
            tr.indices.deinit();
            return err;
        };

        tr.textMesh = Mesh.init();

        tr.screen_size = orthoSize;

        tr.projection_mat = vmath.mat4.createOrthogonal(0, orthoSize[0], orthoSize[1], 0, 0.01, 100.0);
        //tr.projection_mat = vmath.mat4.createOrthogonal(0, orthoSize[0], 0, orthoSize[1], 0.01, 100.0);

        return tr;
    }

    pub fn begin_text_pass(self: *Self) void {
        self.vertices.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
    }

    inline fn write_standard_vertex(position: vec3, uv: vec2, color: vec3, vertex_span: *[8]f32) void {
        vertex_span[0] = position[0];
        vertex_span[1] = position[1];
        vertex_span[2] = position[2];
        vertex_span[3] = uv[0];
        vertex_span[4] = uv[1];
        vertex_span[5] = color[0];
        vertex_span[6] = color[1];
        vertex_span[7] = color[2];
    }

    pub fn add_char(self: *Self, char: u8, base_position: vec2, position: vec2, color: vec3) !vec2 {
        const glyph, const nextCursor = try switch (char) {
            '\n', '\r', '\t' => self.fontBuffer.get_glyph('|', position),
            else => self.fontBuffer.get_glyph(char, position),
        };

        if (char == '\n') {
            return vec2{ base_position[0], glyph.bottom_right[1] + 2 };
        } else if (char == '\t') {
            const cur = nextCursor orelse position;
            return vec2{ cur[0] + 2 * (glyph.bottom_right[0] - glyph.top_left[0]), cur[1] };
        } else if (char == '\r') {
            return vec2{ base_position[0], position[1] };
        }

        const floats_per_vertex = self.vertexFormat.stride / @sizeOf(f32);

        const vertex_length = self.vertices.items.len / floats_per_vertex;
        //const index_length = self.indices.items.len;

        const vspan: []f32 = try self.vertices.addManyAsSlice(4 * floats_per_vertex);
        const ispan: []u32 = try self.indices.addManyAsSlice(6);

        //std.debug.print("new-verts: {d}:{d}, new-ind: {d}:{d}\n", .{ vspan.len, vertex_length, ispan.len, index_length });

        write_standard_vertex(vec3{ glyph.top_left[0], glyph.top_left[1], -1 }, glyph.uv0, color, vspan[0..8]);
        write_standard_vertex(vec3{ glyph.bottom_right[0], glyph.top_left[1], -1 }, vec2{ glyph.uv1[0], glyph.uv0[1] }, color, vspan[8..16]);
        write_standard_vertex(vec3{ glyph.bottom_right[0], glyph.bottom_right[1], -1 }, glyph.uv1, color, vspan[16..24]);
        write_standard_vertex(vec3{ glyph.top_left[0], glyph.bottom_right[1], -1 }, vec2{ glyph.uv0[0], glyph.uv1[1] }, color, vspan[24..32]);

        ispan[0] = @intCast(vertex_length);
        ispan[1] = @intCast(vertex_length + 1);
        ispan[2] = @intCast(vertex_length + 3);
        ispan[3] = @intCast(vertex_length + 3);
        ispan[4] = @intCast(vertex_length + 1);
        ispan[5] = @intCast(vertex_length + 2);

        return nextCursor orelse position;
    }

    pub fn add_text(self: *Self, position: vec2, text: []const u8, color: vec3) !vec2 {
        var cursor = position;

        for (text) |char| {
            cursor = try self.add_char(char, position, cursor, color);
        }

        return cursor;
    }

    pub fn end_text_pass(self: *Self) !void {
        try self.textMesh.upload(self.vertices.items, self.indices.items, self.vertexFormat);
    }

    pub fn render(self: Self, shader_location_for_atlas: i32, slot_for_atlas: u32) void {
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);

        set_uniform_texture(shader_location_for_atlas, slot_for_atlas, self.fontAtlas);
        self.textMesh.present(Primitive.Triangles);

        gl.glDisable(gl.GL_BLEND);
    }
};

pub const VisualGlyph = struct {
    top_left: vec2,
    bottom_right: vec2,
    uv0: vec2,
    uv1: vec2,
};

pub fn AllocateFontBuffer(allocator: std.mem.Allocator, config: FontAtlasConfig) !FontBuffer {
    const buffer = try allocator.alloc(u8, config.width * config.height);
    const charbuf = allocator.alloc(ttf.stbtt_packedchar, (config.end_char - config.begin_char + 1)) catch |err| {
        allocator.free(buffer);
        return err;
    };
    return FontBuffer{
        .atlas_data = buffer,
        .char_data = charbuf,
        .config = config,
    };
}

pub fn FreeFontBuffer(allocator: std.mem.Allocator, buffer: FontBuffer) void {
    allocator.free(buffer.char_data);
    allocator.free(buffer.atlas_data);
}

pub fn PackFontAtlas(font: []u8, buffer: *FontBuffer) !void {
    var ctx: ttf.stbtt_pack_context = undefined;

    if (ttf.stbtt_PackBegin(&ctx, @ptrCast(buffer.atlas_data.ptr), @intCast(buffer.config.width), @intCast(buffer.config.height), 0, 1, null) == 0) {
        return error.PackingFailure;
    }
    defer ttf.stbtt_PackEnd(&ctx);

    if (buffer.config.oversample > 0) {
        ttf.stbtt_PackSetOversampling(&ctx, @intCast(buffer.config.oversample), @intCast(buffer.config.oversample));
    }

    if (ttf.stbtt_PackFontRange(&ctx, @ptrCast(font.ptr), 0, buffer.config.font_size, @intCast(buffer.config.begin_char), @intCast(buffer.config.end_char - buffer.config.begin_char + 1), @ptrCast(buffer.char_data.ptr)) == 0) {
        return error.PackingFailure;
    }
}

pub fn LoadBinaryFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, std.fs.File.OpenFlags{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    const buffer = try allocator.alloc(u8, stat.size);
    _ = file.readAll(buffer) catch |err| {
        allocator.free(buffer);
        return err;
    };

    return buffer;
}

//--------------------------------------------
// INPUT
//--------------------------------------------
// This is a lightweight wrapper around sdl events
// with the purpose of providing a quick way of
// getting started with basic events without
// having to directly interface with them. You
// can absolutely interact with SDL directly if
// you need to
//--------------------------------------------

pub fn CreateEventHooks(comptime ctx_t: type, comptime err: type) type {
    return struct {
        pub const EventHooks: type = struct {
            on_quit: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            on_key_down: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            on_key_up: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            on_mouse_down: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            on_mouse_up: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            on_mouse_move: ?*const fn (event: EventTy, ctx: ?*ctx_t) err!void = null,
            last_frame_time: u64 = 0,
            current_frame_time: u64 = 0,
            delta_time: f64 = 0,
        };

        pub fn PollEvents(hooks: *EventHooks, ctx: ?*ctx_t) err!void {
            comptime {
                if (@typeInfo(err) != .error_set) {
                    @compileError("Expected error set as parameter, 'err' parameter is not an errorset.");
                }
            }

            const CONVERT: f64 = 1 / 1e9;

            hooks.current_frame_time = sdl.SDL_GetTicksNS();
            hooks.delta_time = @floatFromInt((hooks.current_frame_time - hooks.last_frame_time));
            hooks.delta_time *= CONVERT;
            hooks.last_frame_time = hooks.current_frame_time;

            var event: EventTy = undefined;
            while (sdl.SDL_PollEvent(&event)) {
                switch (event.type) {
                    sdl.SDL_EVENT_QUIT => {
                        if (hooks.on_quit) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    sdl.SDL_EVENT_KEY_DOWN => {
                        if (hooks.on_key_down) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    sdl.SDL_EVENT_KEY_UP => {
                        if (hooks.on_key_up) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_BUTTON_DOWN => {
                        if (hooks.on_mouse_down) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_BUTTON_UP => {
                        if (hooks.on_mouse_up) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    sdl.SDL_EVENT_MOUSE_MOTION => {
                        if (hooks.on_mouse_move) |hook| {
                            try hook(event, ctx);
                        }
                    },
                    else => {},
                }
            }
        }
    };
}

pub fn SetMouseCaptured(capture: bool) void {
    _ = sdl.SDL_SetWindowRelativeMouseMode(window, capture);
}
