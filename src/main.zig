const std = @import("std");
const gfx = @import("gfx.zig");

const gl = gfx.gl;
const sdl = gfx.sdl;

const EventErrors = error{
    NullContext,
};

const Camera = struct {
    position: gfx.vec3,
    eye_offset: gfx.vec3,
    orientation: gfx.Quat,
    fov: f32 = std.math.pi / 2.0,
    zNear: f32 = 0.01,
    zFar: f32 = 1000.0,

    pub fn get_perspective(self: Camera, aspect: f32) gfx.mat4 {
        return gfx.mat4.createPerspective(self.fov, aspect, self.zNear, self.zFar);
    }
    pub fn get_view(self: Camera) gfx.mat4 {
        // How to get look direction
        const forward = self.get_forward();
        const eye = self.position + self.eye_offset;
        const center = eye + forward;
        return gfx.mat4.createLookAt(eye, center, gfx.vec3{ 0, 1, 0 });
    }

    pub fn get_forward(self: Camera) gfx.vec3 {
        return gfx.Quat.rotate_vec3(self.orientation, gfx.vec3{ 0, 0, -1 });
    }

    pub fn get_right(self: Camera) gfx.vec3 {
        return gfx.Quat.rotate_vec3(self.orientation, gfx.vec3{ 1, 0, 0 });
    }
};

const Settings = struct {
    camera_sensitivity: f32,
    camera_smoothing: f32,
    player_speed: f32,
};

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
    player: Camera,
    input: InputContext = InputContext{},
    settings: Settings = Settings{
        .camera_sensitivity = 0.01,
        .camera_smoothing = 0.2,
        .player_speed = 0.001,
    },
};

const EventHooks = gfx.CreateEventHooks(Context, EventErrors);
const EventHooksType = EventHooks.EventHooks;

pub fn main() !void {
    gfx.ShowSDLErrors = true;

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
        .player = Camera{
            .position = @splat(0.0),
            .eye_offset = gfx.vec3{ 0, 1, 0 },
            .orientation = gfx.Quat.identity,
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
    const model = gfx.mat4.createScale(10, 0, 10); //gfx.mat4.scale(10, 10, 10);
    const shader = gfx.Shader.create_from_file("vertex.glsl", "fragment.glsl", std.heap.page_allocator) catch |err| val: {
        if (err == error.FileNotFound) {
            break :val try gfx.Shader.create_from_file("zig-out/bin/vertex.glsl", "zig-out/bin/fragment.glsl", std.heap.page_allocator);
        } else {
            return err;
        }
    };

    defer shader.destroy();

    const loc_u_Projection = gfx.get_uniform_location(shader, "u_Projection");
    const loc_u_View = gfx.get_uniform_location(shader, "u_View");
    const loc_u_Model = gfx.get_uniform_location(shader, "u_Model");
    const loc_u_Albedo = gfx.get_uniform_location(shader, "u_Albedo");

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

    const textureSettings = gfx.TextureSettings{
        .gen_mipmaps = true,
        .mag_sample_policy = gfx.SamplePolicy.Nearest,
        .min_sample_policy = gfx.SamplePolicy.Nearest,
        .texture_policy = gfx.TexturePolicy.Repeat,
    };
    const texture = try gfx.UploadImage(image, textureSettings);

    gfx.SetMouseCaptured(true);

    while (context.running) {
        @memcpy(context.input.lastFrame[0..context.input.lastFrame.len], context.input.currentFrame[0..context.input.currentFrame.len]);
        try EventHooks.PollEvents(eventHooks, &context);

        gl.glClearColor(0.0, 0.0, 0.01, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        const view = context.player.get_view();

        process_player_move(&context);

        shader.bind();

        gfx.set_uniform(gfx.mat4, loc_u_Projection, projection);
        gfx.set_uniform(gfx.mat4, loc_u_View, view);
        gfx.set_uniform(gfx.mat4, loc_u_Model, model);
        gfx.set_uniform_texture(loc_u_Albedo, 0, texture);

        mesh.present(gfx.Primitive.Triangles);

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
    const iForward: i32 = @intFromBool(ctx.input.currentFrame[@as(i32, @intFromEnum(InputContext.Buttons.Forward))]) - @as(i32, @intFromBool(ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Back)]));
    const iRight: i32 = @intFromBool(ctx.input.currentFrame[@as(i32, @intFromEnum(InputContext.Buttons.Right))]) - @as(i32, @intFromBool(ctx.input.currentFrame[@intFromEnum(InputContext.Buttons.Left)]));

    const iCombined = gfx.vec3{ @floatFromInt(iRight), 0, @floatFromInt(-iForward) };

    if (@abs(gfx.dot(gfx.vec3, iCombined, iCombined)) <= std.math.floatEps(f32)) {
        return;
    }

    const inputRaw = gfx.normalize(gfx.vec3, iCombined);
    var velocity = gfx.Quat.rotate_vec3(ctx.player.orientation, inputRaw);
    velocity[1] = 0;
    velocity = gfx.normalize(gfx.vec3, velocity) * @as(gfx.vec3, @splat(ctx.settings.player_speed));

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

        const yaw = gfx.Quat.angle_axis(-delta_x, gfx.vec3{ 0, 1, 0 });

        orientation = gfx.Quat.normalize(gfx.Quat.mul(yaw, orientation));

        const rightAxis = gfx.Quat.rotate_vec3(orientation, gfx.vec3{ 1, 0, 0 });

        const pitch = gfx.Quat.angle_axis(-delta_y, rightAxis);

        orientation = gfx.Quat.normalize(gfx.Quat.mul(pitch, orientation));

        const forward = gfx.normalize(gfx.vec3, gfx.Quat.rotate_vec3(orientation, gfx.vec3{ 0, 0, -1 }));
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

        const correction = gfx.Quat.angle_axis(dif, rightAxis);
        orientation = gfx.Quat.mul(correction, orientation);

        ctx.player.orientation = gfx.Quat.normalize(gfx.Quat.slerp(ctx.player.orientation, orientation, ctx.settings.camera_smoothing));
        return;
    }
    return error.NullContext;
}
