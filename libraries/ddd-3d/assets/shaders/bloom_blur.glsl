extern vec2 u_direction;
extern number u_radius;

#ifdef PIXEL
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec2 step_uv = u_direction * u_radius;
    vec3 result = Texel(texture, texture_coords).rgb * 0.227027;
    result += Texel(texture, texture_coords + step_uv * 1.384615).rgb * 0.316216;
    result += Texel(texture, texture_coords - step_uv * 1.384615).rgb * 0.316216;
    result += Texel(texture, texture_coords + step_uv * 3.230769).rgb * 0.070270;
    result += Texel(texture, texture_coords - step_uv * 3.230769).rgb * 0.070270;
    return vec4(result * color.rgb, 1.0);
}
#endif
