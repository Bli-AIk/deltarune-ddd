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
extern number u_specular_strength;
extern number u_ambient_reflection;
extern number u_double_sided;
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

vec3 fresnelSchlick(vec3 base_reflectivity, float normal_view)
{
    float grazing = pow(1.0 - clamp(normal_view, 0.0, 1.0), 5.0);
    return base_reflectivity + (vec3(1.0) - base_reflectivity) * grazing;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec4 base = u_base_color * color;
    if (u_alpha_mask > 0.5 && base.a < u_alpha_cutoff) {
        discard;
    }

    vec3 normal = normalize(v_world_normal);
    if (u_double_sided > 0.5 && !gl_FrontFacing) {
        normal = -normal;
    }
    vec3 to_light = normalize(-u_light_direction);
    vec3 to_camera = normalize(u_camera_position - v_world_position);
    vec3 halfway = normalize(to_light + to_camera);

    float metallic = clamp(u_metallic, 0.0, 1.0);
    float roughness = clamp(u_roughness, 0.04, 1.0);
    float normal_light = max(dot(normal, to_light), 0.0);
    float normal_halfway = max(dot(normal, halfway), 0.0);
    float normal_view = max(dot(normal, to_camera), 0.0);
    // The square-root response keeps narrow metal forms readable while still
    // shrinking highlights as a material becomes smoother.
    float shininess = mix(48.0, 4.0, sqrt(roughness));
    float specular_lobe = pow(normal_halfway, shininess);
    float normalized_specular = specular_lobe * (shininess + 2.0) * 0.07957747;
    vec3 base_reflectivity = mix(vec3(0.04), base.rgb, metallic);
    vec3 fresnel = fresnelSchlick(base_reflectivity, normal_view);
    vec3 diffuse_color = base.rgb * (1.0 - metallic) * (vec3(1.0) - fresnel);

    // There is no environment map in the compact renderer. Approximate a
    // directional ambient reflection without changing direct-light semantics.
    float ambient_metal_weight = mix(0.18, 1.0, metallic) * u_ambient_reflection;
    float ambient_alignment = 0.25 + 0.75 * abs(dot(normal, to_light));
    vec3 reflected_ambient = mix(u_ambient_color, u_light_color, 0.35);
    vec3 ambient = u_ambient_color * diffuse_color;
    ambient += reflected_ambient * fresnel * ambient_metal_weight * ambient_alignment;
    vec3 direct_diffuse = diffuse_color * normal_light;
    vec3 direct_specular = fresnel * normalized_specular * normal_light * u_specular_strength;
    vec3 lit = ambient + u_light_color * (direct_diffuse + direct_specular);
    lit += u_emissive;
    return vec4(lit, base.a);
}
#endif
