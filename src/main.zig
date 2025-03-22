const std = @import("std");
const gfx = @import("gfx.zig");
const vmt = @import("vmath.zig");
const ecs = @import("ecs.zig");

const gl = gfx.gl;
const sdl = gfx.sdl;

const EventErrors = error{
    NullContext,
};

const Camera = struct {
    position: vmt.vec3,
    eye_offset: vmt.vec3,
    orientation: vmt.quat,
    fov: f32 = std.math.pi / 2.0,
    zNear: f32 = 0.01,
    zFar: f32 = 1000.0,

    pub fn get_perspective(self: Camera, aspect: f32) vmt.mat4 {
        return vmt.mat4.createPerspective(self.fov, aspect, self.zNear, self.zFar);
    }
    pub fn get_view(self: Camera) vmt.mat4 {
        // How to get look direction
        const forward = self.get_forward();
        const eye = self.position + self.eye_offset;
        const center = eye + forward;
        return vmt.mat4.createLookAt(eye, center, vmt.vec3{ 0, 1, 0 });
    }

    pub fn get_forward(self: Camera) vmt.vec3 {
        return vmt.quat.rotate_vec3(self.orientation, vmt.vec3{ 0, 0, -1 });
    }

    pub fn get_right(self: Camera) vmt.vec3 {
        return vmt.quat.rotate_vec3(self.orientation, vmt.vec3{ 1, 0, 0 });
    }
};

const Settings = struct {
    camera_sensitivity: f32,
    camera_smoothing: f32,
    player_speed: f32,
};

const Transformation = struct {
    position: vmt.vec3,
};

const Registry = ecs.DefineRegistry(&[_]type{Transformation}, &[_]u64{100}, "main");

const InputContext = struct {
    currentFrame: [@intFromEnum(Buttons.ENDINDEX)]bool = undefined,
    lastFrame: [@intFromEnum(Buttons.ENDINDEX)]bool = undefined,

    pub const Buttons = enum {
        Forward,
        Back,
        Left,
        Right,
        Jump,
        Interact1,
        Interact2,
        ENDINDEX,
    };
};

const Context = struct {
    running: bool,
    delta_time: f64,
    player: Camera,
    input: InputContext = InputContext{},
    settings: Settings = Settings{
        .camera_sensitivity = 0.01,
        .camera_smoothing = 0.2,
        .player_speed = 10.0,
    },
};

const EventHooks = gfx.CreateEventHooks(Context, EventErrors);
const EventHooksType = EventHooks.EventHooks;

pub fn main() !void {
    gfx.ShowSDLErrors = true;

    const info = @typeInfo(Registry);
    const fields: []const std.builtin.Type.StructField = switch (info) {
        .@"struct" => |*str| str.fields,
        else => &[_]std.builtin.Type.StructField{},
    };

    if (fields.len == 0) {
        std.debug.print("info: {}\n", .{info});
    }

    var stdout = std.io.getStdOut().writer();

    inline for (fields) |field| {
        try stdout.print("Field name: {s}\n", .{field.name});
    }

    std.debug.print("{}\n", .{Registry});

    var registry = Registry{
        .Transformation = undefined,
    };

    registry.Transformation[0] = Transformation{ .position = vmt.vec3{ 0, -10, 0 } };
    std.debug.print("{}\n", .{registry.Transformation[0]});

    const params = gfx.InitParams{
        .title = "Hello OpenGL",
        .width = 800,
        .height = 600,
        .version = gfx.GLVersion{ .major = 3, .minor = 3, .core = true },
    };
    try gfx.Init(params);
    defer gfx.Quit();

    var context = Context{
        .running = true,
        .delta_time = 0.0,
        .player = Camera{
            .position = @splat(0.0),
            .eye_offset = vmt.vec3{ 0, 1, 0 },
            .orientation = vmt.quat.identity,
        },
    };

    var vfmt = gfx.VertexFormatBuffer{};
    try vfmt.add_attribute(gfx.VertexType.Float3); // position
    try vfmt.add_attribute(gfx.VertexType.Float3); // color
    try vfmt.add_attribute(gfx.VertexType.Float2); // uv

    const vertices = [_]f32{
        -0.5, 0.0, -0.5, 1.0, 0.0, 0.0, 0, 0,
        0.5,  0.0, -0.5, 0.0, 1.0, 0.0, 1, 0,
        -0.5, 0.0, 0.5,  0.0, 0.0, 1.0, 0, 1,
        0.5,  0.0, 0.5,  1.0, 1.0, 1.0, 1, 1,
    };
    const indices = [_]u32{ 0, 1, 2, 1, 2, 3 };

    var mesh = gfx.Mesh.init();
    try mesh.upload(&vertices, &indices, vfmt);
    defer mesh.destroy();
    gfx.DebugPrintGLErrors();

    const projection = context.player.get_perspective(@as(f32, params.width) / @as(f32, params.height)); //gfx.mat4.createPerspective(3.1415926 / 2.0, @as(f32, params.width) / @as(f32, params.height), 0.01, 1000.0);

    //const view = gfx.mat4.createLookAt(gfx.vec3{ 0, 1, 0 }, gfx.vec3{ 0, 1, -1 }, gfx.vec3{ 0, 1, 0 });
    const model = vmt.mat4.createScale(10, 0, 10); //gfx.mat4.scale(10, 10, 10);
    const shader = gfx.Shader.create_from_file("vertex.glsl", "fragment.glsl", std.heap.page_allocator) catch |err| val: {
        if (err == error.FileNotFound) {
            break :val try gfx.Shader.create_from_file("zig-out/bin/vertex.glsl", "zig-out/bin/fragment.glsl", std.heap.page_allocator);
        } else {
            return err;
        }
    };

    const text_shader = gfx.Shader.create_from_file("text_vertex.glsl", "text_fragment.glsl", std.heap.page_allocator) catch |err| val: {
        if (err == error.FileNotFound) {
            break :val try gfx.Shader.create_from_file("zig-out/bin/text_vertex.glsl", "zig-out/bin/text_fragment.glsl", std.heap.page_allocator);
        } else {
            return err;
        }
    };

    defer text_shader.destroy();
    defer shader.destroy();

    const loc_u_Projection = gfx.get_uniform_location(shader, "u_Projection");
    const loc_u_View = gfx.get_uniform_location(shader, "u_View");
    const loc_u_Model = gfx.get_uniform_location(shader, "u_Model");
    const loc_u_Albedo = gfx.get_uniform_location(shader, "u_Albedo");

    const loc_u_TextProjection = gfx.get_uniform_location(text_shader, "u_Projection");
    const loc_u_TextAtlas = gfx.get_uniform_location(text_shader, "u_Atlas");

    const eventHooks = EventHooksType{
        .on_quit = on_quit,
        .on_mouse_move = on_mouse_move,
        .on_key_down = on_key_pressed,
        .on_key_up = on_key_released,
        .on_mouse_down = on_mouse_button_down,
        .on_mouse_up = on_mouse_button_up,
    };

    const image = gfx.LoadImage("Playful.png") catch val: {
        break :val try gfx.LoadImage("zig-out/bin/Playful.png");
    };
    defer gfx.DestroyImage(image);

    const font_data = gfx.LoadBinaryFile(std.heap.page_allocator, "8bitOperatorPlus-Regular.ttf") catch |err| val: {
        if (err == error.FileNotFound) {
            break :val try gfx.LoadBinaryFile(std.heap.page_allocator, "zig-out/bin/8bitOperatorPlus-Regular.ttf");
        } else {
            return err;
        }
    };

    const fontConfig = gfx.FontAtlasConfig{
        .font_size = 16.0,
        .oversample = 0,
    };

    var textRenderer = try gfx.TextRenderer.init_with_defaults(std.heap.page_allocator, font_data, fontConfig, vmt.vec2{ @floatFromInt(params.width), @floatFromInt(params.height) });

    const textureSettings = gfx.TextureSettings{
        .gen_mipmaps = true,
        .mag_sample_policy = gfx.SamplePolicy.Nearest,
        .min_sample_policy = gfx.SamplePolicy.Nearest,
        .texture_policy = gfx.TexturePolicy.Repeat,
    };
    const texture = try gfx.UploadImage(image, textureSettings);

    gfx.SetMouseCaptured(true);

    var frameTimer = gfx.Timer.Now();
    while (context.running) {
        @memcpy(context.input.lastFrame[0..context.input.lastFrame.len], context.input.currentFrame[0..context.input.currentFrame.len]);

        context.delta_time = frameTimer.delta_time();
        try EventHooks.PollEvents(eventHooks, &context);

        gl.glClearColor(0.0, 0.0, 0.01, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        const view = context.player.get_view();

        process_player_move(&context);

        shader.bind();

        gfx.set_uniform(loc_u_Projection, projection);
        gfx.set_uniform(loc_u_View, view);
        gfx.set_uniform(loc_u_Model, model);
        gfx.set_uniform_texture(loc_u_Albedo, 0, texture);

        mesh.present(gfx.Primitive.Triangles);

        textRenderer.begin_text_pass();
        {
            var nextPos = try textRenderer.add_text(vmt.vec2{ 10, 32 }, "Hello ", vmt.vec3{ 1, 1, 1 });
            nextPos = try textRenderer.add_text(nextPos, "World", vmt.vec3{ 1, 0, 0 });

            nextPos = vmt.vec2{ 10, 48 };
            nextPos = try textRenderer.add_text(nextPos, "(X, Y, Z): (", vmt.vec3{ 1, 1, 1 });

            var buffer: [128]u8 = undefined;
            var str = try std.fmt.bufPrint(&buffer, "{d:.2}", .{context.player.position[0]});
            nextPos = try textRenderer.add_text(nextPos, str, vmt.vec3{ 1, 0, 0 });
            nextPos = try textRenderer.add_text(nextPos, ", ", vmt.vec3{ 1, 1, 1 });
            str = try std.fmt.bufPrint(&buffer, "{d:.2}", .{context.player.position[1]});
            nextPos = try textRenderer.add_text(nextPos, str, vmt.vec3{ 0, 1, 0 });
            nextPos = try textRenderer.add_text(nextPos, ", ", vmt.vec3{ 1, 1, 1 });
            str = try std.fmt.bufPrint(&buffer, "{d:.2}", .{context.player.position[2]});
            nextPos = try textRenderer.add_text(nextPos, str, vmt.vec3{ 0, 0, 1 });
            nextPos = try textRenderer.add_text(nextPos, ")", vmt.vec3{ 1, 1, 1 });
        }
        try textRenderer.end_text_pass();

        text_shader.bind();
        gfx.set_uniform(loc_u_TextProjection, textRenderer.projection_mat);
        textRenderer.render(loc_u_TextAtlas, 0);

        gfx.SwapBuffers();
        gfx.DebugPrintGLErrors();
    }

    gfx.SetMouseCaptured(false);
}

fn on_quit(_: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        ctx.running = false;
        return;
    }
    return error.NullContext;
}

fn initialize_input(ctx: *Context) void {
    inline for (0..ctx.input.currentFrame.len) |i| {
        ctx.input.currentFrame[i] = false;
        ctx.input.lastFrame[i] = false;
    }
}

fn process_player_move(ctx: *Context) void {
    const delta_time: f32 = @floatCast(ctx.delta_time);
    const iForward: i32 = @intFromBool(ctx.input.currentFrame[@as(i32, @intFromEnum(InputContext.Buttons.Forward))]) - @as(i32, @intFromBool(ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Back)]));
    const iRight: i32 = @intFromBool(ctx.input.currentFrame[@as(i32, @intFromEnum(InputContext.Buttons.Right))]) - @as(i32, @intFromBool(ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Left)]));

    const iCombined = vmt.vec3{ @floatFromInt(iRight), 0, @floatFromInt(-iForward) };

    if (@abs(vmt.dot(iCombined, iCombined)) <= std.math.floatEps(f32)) {
        return;
    }

    const inputRaw = vmt.normalize(iCombined);
    var velocity = vmt.quat.rotate_vec3(ctx.player.orientation, inputRaw);
    velocity[1] = 0;
    velocity = vmt.normalize(velocity) * @as(vmt.vec3, @splat(ctx.settings.player_speed * delta_time));

    ctx.player.position += velocity;
}

fn on_key_released(event: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        switch (event.key.scancode) {
            sdl.SDL_SCANCODE_W => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Forward)] = false,
            sdl.SDL_SCANCODE_S => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Back)] = false,
            sdl.SDL_SCANCODE_A => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Left)] = false,
            sdl.SDL_SCANCODE_D => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Right)] = false,
            sdl.SDL_SCANCODE_SPACE => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Jump)] = false,
            else => {},
        }

        return;
    }

    return error.NullContext;
}

fn on_key_pressed(event: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        switch (event.key.scancode) {
            sdl.SDL_SCANCODE_W => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Forward)] = true,
            sdl.SDL_SCANCODE_S => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Back)] = true,
            sdl.SDL_SCANCODE_A => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Left)] = true,
            sdl.SDL_SCANCODE_D => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Right)] = true,
            sdl.SDL_SCANCODE_SPACE => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Jump)] = true,
            sdl.SDL_SCANCODE_ESCAPE => ctx.running = false,
            else => {},
        }

        return;
    }

    return error.NullContext;
}

fn on_mouse_button_down(event: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        switch (event.button.button) {
            sdl.SDL_BUTTON_LEFT => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Interact1)] = true,
            sdl.SDL_BUTTON_RIGHT => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Interact2)] = true,
            else => {},
        }

        return;
    }

    return error.NullContext;
}

fn on_mouse_button_up(event: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        switch (event.button.button) {
            sdl.SDL_BUTTON_LEFT => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Interact1)] = false,
            sdl.SDL_BUTTON_RIGHT => ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Interact2)] = false,
            else => {},
        }

        return;
    }

    return error.NullContext;
}

// Quaternion multiplication is not communicative.
// we want Pitch * (Yaw * Original)

fn on_mouse_move(event: gfx.EventTy, context: ?*Context) EventErrors!void {
    if (context) |ctx| {
        const delta_x = event.motion.xrel * ctx.settings.camera_sensitivity;
        const delta_y = event.motion.yrel * ctx.settings.camera_sensitivity;

        std.debug.assert(0.0 <= ctx.settings.camera_smoothing and ctx.settings.camera_smoothing <= 1.0);

        var orientation = ctx.player.orientation;

        const yaw = vmt.quat.angle_axis(-delta_x, vmt.vec3{ 0, 1, 0 });

        orientation = vmt.quat.normalize(vmt.quat.mul(yaw, orientation));

        const rightAxis = vmt.quat.rotate_vec3(orientation, vmt.vec3{ 1, 0, 0 });

        const pitch = vmt.quat.angle_axis(-delta_y, rightAxis);

        orientation = vmt.quat.normalize(vmt.quat.mul(pitch, orientation));

        const forward = vmt.normalize(vmt.quat.rotate_vec3(orientation, vmt.vec3{ 0, 0, -1 }));
        const theta = std.math.asin(forward[1]); // angle of forward vector

        const MAX = std.math.degreesToRadians(75.0);
        const MIN = std.math.degreesToRadians(-75.0);

        // clamped angle, if theta is already in range theta will equal theta_p
        // if theta is outside of the range, theta will not equal theta_p
        const theta_p = std.math.clamp(theta, MIN, MAX);

        // difference between theta_p and theta will serve as a corrective rotation to move theta back in range
        // if theta is already in range, the dif will be zero and a zero degree rotation will be applied
        const dif = theta_p - theta;

        //std.debug.print("\r\x1b[2K Th: {d}, Th': {d} -> dif: {d}  [{d}, {d}]", .{ theta, theta_p, dif, MIN, MAX });

        const correction = vmt.quat.angle_axis(dif, rightAxis);
        orientation = vmt.quat.mul(correction, orientation);

        ctx.player.orientation = vmt.quat.normalize(vmt.quat.slerp(ctx.player.orientation, orientation, ctx.settings.camera_smoothing));
        return;
    }
    return error.NullContext;
}
