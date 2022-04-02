//! OpenGL bindings.
//!
//! These are pupose-built for usage within this program. While they closely
//! align with the OpenGL C APIs, they aren't meant to be general purpose.
//! Certain use cases will CERTAINLY be sub-optimal by using these helpers
//! and should use the C API directly.
//!
//! For performance-intensive or unsupported aspects of OpenGL, the C
//! API is exposed via the `c` constant.

pub const c = @import("opengl/c.zig");
pub const Buffer = @import("opengl/Buffer.zig");
pub const Program = @import("opengl/Program.zig");
pub const Shader = @import("opengl/Shader.zig");
pub const VertexArray = @import("opengl/VertexArray.zig");
