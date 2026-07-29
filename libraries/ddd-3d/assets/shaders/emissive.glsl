extern mat4 u_model;
extern mat4 u_view_projection;
extern vec4 u_base_color;
extern vec3 u_emissive;
extern number u_alpha_cutoff;
extern number u_alpha_mask;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    return u_view_projection * u_model * vertex_position;
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 base = u_base_color * color;
    if (u_alpha_mask > 0.5 && base.a < u_alpha_cutoff) {
        discard;
    }
    return vec4(base.rgb + u_emissive, base.a);
}
#endif
