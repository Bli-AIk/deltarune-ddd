extern vec3 u_fog_color;
extern number u_fog_strength;
extern number u_vignette;
extern Image u_bloom_texture;
extern number u_bloom_enabled;
extern number u_bloom_strength;
extern vec3 u_bloom_tint;

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 source = Texel(texture, texture_coords) * color;
    vec2 centered = texture_coords - vec2(0.5);
    float radial_distance = dot(centered, centered) * 4.0;
    float edge = smoothstep(0.15, 1.0, radial_distance);
    source.rgb = mix(source.rgb, u_fog_color, clamp(u_fog_strength, 0.0, 1.0) * source.a);
    if (u_bloom_enabled > 0.5) {
        vec3 bloom = Texel(u_bloom_texture, texture_coords).rgb;
        source.rgb += bloom * u_bloom_tint * max(u_bloom_strength, 0.0);
        // Preserve a tight halo on tiny emissive edges after the half-resolution
        // pass has been filtered. This keeps one-pixel suit tubes readable at
        // low output resolutions without turning the whole scene hazy.
        vec3 local_highlight = max(source.rgb - vec3(0.14), vec3(0.0));
        source.rgb += local_highlight * u_bloom_tint * max(u_bloom_strength, 0.0) * 0.12;
    }
    source.rgb *= 1.0 - clamp(u_vignette, 0.0, 1.0) * edge;
    return source;
}
#endif
