# King Battle Metal Textures

`blue_metal_plate_diff_1k.jpg`, `blue_metal_plate_nor_gl_1k.jpg`, and
`blue_metal_plate_rough_1k.jpg` are derived directly from Poly Haven's
**Blue Metal Plate** texture set by Rob Tuytel.

- Source: https://polyhaven.com/a/blue_metal_plate
- License: CC0 1.0 Universal
- Resolution: 1024 x 1024
- Maps: albedo, OpenGL tangent-space normal, and roughness

Blender's material graph tints the albedo toward the scene palette. The
runtime currently samples the normal and roughness maps conservatively while
the authored scene preset controls the base color. These assets are assigned
only to the cage and chain material definitions; suit materials remain
geometry-led and untextured.
