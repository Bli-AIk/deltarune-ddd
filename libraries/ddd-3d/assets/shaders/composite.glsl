extern vec3 u_fog_color;
extern number u_fog_strength;
extern number u_vignette;

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 source = Texel(texture, texture_coords) * color;
    vec2 centered = texture_coords - vec2(0.5);
    float radial_distance = dot(centered, centered) * 4.0;
    float edge = smoothstep(0.15, 1.0, radial_distance);
    source.rgb = mix(source.rgb, u_fog_color, clamp(u_fog_strength, 0.0, 1.0) * source.a);
    source.rgb *= 1.0 - clamp(u_vignette, 0.0, 1.0) * edge;
    return source;
}
#endif
