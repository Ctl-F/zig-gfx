const std = @import("std");
const gfx = @import("gfx.zig");

const gl = gfx.gl;
const sdl = gfx.sdl;

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

    var vfmt = gfx.VertexFormatBuffer{};
    try vfmt.add_attribute(gfx.VertexType.Float3); // position
    try vfmt.add_attribute(gfx.VertexType.Float3); // color

    const vertices = [_]f32{
        -0.5, 0.0, -0.5, 1.0, 0.0, 0.0,
        0.5,  0.0, -0.5, 0.0, 1.0, 0.0,
        -0.5, 0.0, 0.5,  0.0, 0.0, 1.0,
        0.5,  0.0, 0.5,  1.0, 1.0, 1.0,
    };
    const indices = [_]u32{ 0, 1, 2, 1, 2, 3 };

    var mesh = gfx.Mesh.init();
    try mesh.upload(&vertices, &indices, vfmt);
    defer mesh.destroy();
    gfx.DebugPrintGLErrors();

    const projection = gfx.mat4.createPerspective(3.1415926 / 2.0, @as(f32, params.width) / @as(f32, params.height), 0.01, 1000.0);

    const view = gfx.mat4.createLookAt(gfx.vec3{ 0, 1, 0 }, gfx.vec3{ 0, 1, -1 }, gfx.vec3{ 0, 1, 0 });
    const model = gfx.mat4.createScale(10, 0, 10); //gfx.mat4.scale(10, 10, 10);
    const shader = gfx.Shader.create_from_file("vertex.glsl", "fragment.glsl") catch |err| val: {
        if (err == error.FileNotFound) {
            break :val try gfx.Shader.create_from_file("zig-out/bin/vertex.glsl", "zig-out/bin/fragment.glsl");
        } else {
            return err;
        }
    };

    defer shader.destroy();

    const loc_u_Projection = gfx.get_uniform_location(shader, "u_Projection");
    const loc_u_View = gfx.get_uniform_location(shader, "u_View");
    const loc_u_Model = gfx.get_uniform_location(shader, "u_Model");

    main_loop: while (true) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            switch (event.type) {
                sdl.SDL_EVENT_QUIT => break :main_loop,
                else => {},
            }
        }

        gl.glClearColor(0.0, 0.0, 0.01, 1.0);
        gl.glClear(gl.GL_COLOR_BUFFER_BIT);

        shader.bind();

        gfx.set_uniform(gfx.mat4, loc_u_Projection, projection);
        gfx.set_uniform(gfx.mat4, loc_u_View, view);
        gfx.set_uniform(gfx.mat4, loc_u_Model, model);

        mesh.present(gfx.Primitive.Triangles);

        gfx.SwapBuffers();
        gfx.DebugPrintGLErrors();
    }
}
