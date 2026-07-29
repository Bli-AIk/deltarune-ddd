extern mat4 u_model;
extern mat4 u_view_projection;
extern mat3 u_normal_matrix;
extern vec4 u_base_color;
extern vec3 u_emissive;
extern vec3 u_light_direction;
extern vec3 u_light_color;
extern vec3 u_ambient_color;
extern vec3 u_camera_position;
extern number u_metallic;
extern number u_roughness;
extern number u_alpha_cutoff;
extern number u_alpha_mask;

#ifdef VERTEX
attribute vec3 VertexNormal;
varying vec3 v_world_position;
varying vec3 v_world_normal;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 world_position = u_model * vertex_position;
    v_world_position = world_position.xyz;
    v_world_normal = normalize(u_normal_matrix * VertexNormal);
    return u_view_projection * world_position;
}
#endif

#ifdef PIXEL
varying vec3 v_world_position;
varying vec3 v_world_normal;
vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 base = u_base_color * color;
    if (u_alpha_mask > 0.5 && base.a < u_alpha_cutoff) {
        discard;
    }

    vec3 normal = normalize(v_world_normal);
    vec3 to_light = normalize(-u_light_direction);
    vec3 to_camera = normalize(u_camera_position - v_world_position);
    vec3 halfway = normalize(to_light + to_camera);

    float diffuse = max(dot(normal, to_light), 0.0);
    float shininess = mix(96.0, 8.0, clamp(u_roughness, 0.0, 1.0));
    float specular_amount = pow(max(dot(normal, halfway), 0.0), shininess);
    vec3 dielectric_specular = vec3(0.04);
    vec3 specular_color = mix(dielectric_specular, base.rgb, clamp(u_metallic, 0.0, 1.0));
    vec3 diffuse_color = base.rgb * (1.0 - clamp(u_metallic, 0.0, 1.0));
    vec3 lit = u_ambient_color * diffuse_color;
    lit += u_light_color * (diffuse_color * diffuse + specular_color * specular_amount);
    lit += u_emissive;
    return vec4(lit, base.a);
}
#endif
