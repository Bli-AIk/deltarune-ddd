extern number u_threshold;
extern number u_soft_knee;

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec3 source = Texel(texture, texture_coords).rgb * color.rgb;
    float brightness = max(max(source.r, source.g), source.b);
    float knee = max(u_soft_knee, 0.0001);
    float soft = clamp((brightness - u_threshold + knee) / (2.0 * knee), 0.0, 1.0);
    soft = soft * soft * (3.0 - 2.0 * soft);
    float hard = max(brightness - u_threshold, 0.0);
    float contribution = max(hard, soft * knee);
    vec3 extracted = source * contribution / max(brightness, 0.0001);
    return vec4(extracted, 1.0);
}
#endif
