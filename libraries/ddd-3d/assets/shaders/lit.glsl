extern mat4 u_model;
extern mat4 u_view_projection;
extern mat3 u_normal_matrix;
extern vec4 u_base_color;
extern vec3 u_emissive;
extern vec3 u_light_direction;
extern vec3 u_light_color;
extern vec3 u_ambient_color;
extern vec3 u_fill_light_direction;
extern vec3 u_fill_light_color;
extern number u_fill_light_strength;
extern vec3 u_point_light_position_0;
extern vec3 u_point_light_color_0;
extern number u_point_light_strength_0;
extern number u_point_light_range_0;
extern vec3 u_point_light_position_1;
extern vec3 u_point_light_color_1;
extern number u_point_light_strength_1;
extern number u_point_light_range_1;
extern vec3 u_point_light_position_2;
extern vec3 u_point_light_color_2;
extern number u_point_light_strength_2;
extern number u_point_light_range_2;
extern vec3 u_point_light_position_3;
extern vec3 u_point_light_color_3;
extern number u_point_light_strength_3;
extern number u_point_light_range_3;
extern vec3 u_camera_position;
extern number u_metallic;
extern number u_roughness;
extern number u_specular_strength;
extern number u_ambient_reflection;
extern number u_normal_strength;
extern vec2 u_uv_scale;
extern number u_double_sided;
extern number u_alpha_cutoff;
extern number u_alpha_mask;
extern number u_has_base_color_texture;
extern number u_has_normal_texture;
extern number u_has_roughness_texture;
extern Image u_base_color_texture;
extern Image u_normal_texture;
extern Image u_roughness_texture;

#ifdef VERTEX
attribute vec3 VertexNormal;
attribute vec4 VertexTangent;
varying vec3 v_world_position;
varying vec3 v_world_normal;
varying vec4 v_world_tangent;
vec4 position(mat4 transform_projection, vec4 vertex_position)
{
    vec4 world_position = u_model * vertex_position;
    v_world_position = world_position.xyz;
    mat3 model_linear = mat3(u_model);
    float model_handedness = dot(cross(model_linear[0], model_linear[1]), model_linear[2]) < 0.0 ? -1.0 : 1.0;
    // inverse-transpose alone is opposite to geometric winding under a
    // reflection. Align the normal with the transformed triangle surface.
    v_world_normal = normalize(u_normal_matrix * VertexNormal) * model_handedness;
    vec3 world_tangent = normalize(model_linear * VertexTangent.xyz);
    world_tangent = normalize(world_tangent - v_world_normal * dot(v_world_normal, world_tangent));
    v_world_tangent = vec4(world_tangent, VertexTangent.w);
    return u_view_projection * world_position;
}
#endif

#ifdef PIXEL
varying vec3 v_world_position;
varying vec3 v_world_normal;
varying vec4 v_world_tangent;

vec3 fresnelSchlick(vec3 base_reflectivity, float normal_view)
{
    float grazing = pow(1.0 - clamp(normal_view, 0.0, 1.0), 5.0);
    return base_reflectivity + (vec3(1.0) - base_reflectivity) * grazing;
}

vec3 evaluatePointLight(
    vec3 position,
    vec3 color,
    float strength,
    float range,
    vec3 normal,
    vec3 to_camera,
    vec3 fresnel,
    vec3 diffuse_color,
    float shininess,
    float specular_strength
)
{
    vec3 to_point = position - v_world_position;
    float distance_to_point = length(to_point);
    vec3 direction = to_point / max(distance_to_point, 0.0001);
    float falloff = clamp(1.0 - distance_to_point / max(range, 0.0001), 0.0, 1.0);
    falloff *= falloff * max(strength, 0.0);
    vec3 halfway = normalize(direction + to_camera);
    float normal_light = max(dot(normal, direction), 0.0);
    float normal_halfway = max(dot(normal, halfway), 0.0);
    float specular_lobe = pow(normal_halfway, shininess);
    float normalized_specular = specular_lobe * (shininess + 2.0) * 0.07957747;
    return color * (diffuse_color * normal_light + fresnel * normalized_specular * normal_light * specular_strength) * falloff;
}

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords)
{
    vec2 uv = texture_coords * u_uv_scale;
    vec4 base = u_base_color * color;
    if (u_has_base_color_texture > 0.5) {
        base *= Texel(u_base_color_texture, uv);
    }
    if (u_alpha_mask > 0.5 && base.a < u_alpha_cutoff) {
        discard;
    }

    vec3 normal = normalize(v_world_normal);
    float tangent_handedness = v_world_tangent.w;
    if (u_double_sided > 0.5 && !gl_FrontFacing) {
        normal = -normal;
        tangent_handedness = -tangent_handedness;
    }
    if (u_has_normal_texture > 0.5) {
        vec3 tangent = normalize(v_world_tangent.xyz - normal * dot(normal, v_world_tangent.xyz));
        vec3 bitangent = normalize(cross(normal, tangent)) * tangent_handedness;
        vec3 tangent_normal = Texel(u_normal_texture, uv).xyz * 2.0 - 1.0;
        tangent_normal.xy *= u_normal_strength;
        tangent_normal = normalize(tangent_normal);
        normal = normalize(mat3(tangent, bitangent, normal) * tangent_normal);
    }
    vec3 to_light = normalize(-u_light_direction);
    vec3 to_fill_light = normalize(-u_fill_light_direction);
    vec3 to_camera = normalize(u_camera_position - v_world_position);
    vec3 halfway = normalize(to_light + to_camera);
    vec3 fill_halfway = normalize(to_fill_light + to_camera);

    float metallic = clamp(u_metallic, 0.0, 1.0);
    float roughness = u_roughness;
    if (u_has_roughness_texture > 0.5) {
        roughness *= Texel(u_roughness_texture, uv).r;
    }
    roughness = clamp(roughness, 0.04, 1.0);
    float normal_light = max(dot(normal, to_light), 0.0);
    float normal_halfway = max(dot(normal, halfway), 0.0);
    float fill_normal_light = max(dot(normal, to_fill_light), 0.0);
    float fill_normal_halfway = max(dot(normal, fill_halfway), 0.0);
    float normal_view = max(dot(normal, to_camera), 0.0);
    // The square-root response keeps narrow metal forms readable while still
    // shrinking highlights as a material becomes smoother.
    float shininess = mix(48.0, 4.0, sqrt(roughness));
    float specular_lobe = pow(normal_halfway, shininess);
    float normalized_specular = specular_lobe * (shininess + 2.0) * 0.07957747;
    float fill_specular_lobe = pow(fill_normal_halfway, shininess);
    float fill_normalized_specular = fill_specular_lobe * (shininess + 2.0) * 0.07957747;
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
    vec3 fill_diffuse = diffuse_color * fill_normal_light;
    vec3 fill_specular = fresnel * fill_normalized_specular * fill_normal_light * u_specular_strength;
    lit += u_fill_light_color * (fill_diffuse + fill_specular) * u_fill_light_strength;
    lit += evaluatePointLight(
        u_point_light_position_0, u_point_light_color_0, u_point_light_strength_0,
        u_point_light_range_0, normal, to_camera, fresnel, diffuse_color,
        shininess, u_specular_strength
    );
    lit += evaluatePointLight(
        u_point_light_position_1, u_point_light_color_1, u_point_light_strength_1,
        u_point_light_range_1, normal, to_camera, fresnel, diffuse_color,
        shininess, u_specular_strength
    );
    lit += evaluatePointLight(
        u_point_light_position_2, u_point_light_color_2, u_point_light_strength_2,
        u_point_light_range_2, normal, to_camera, fresnel, diffuse_color,
        shininess, u_specular_strength
    );
    lit += evaluatePointLight(
        u_point_light_position_3, u_point_light_color_3, u_point_light_strength_3,
        u_point_light_range_3, normal, to_camera, fresnel, diffuse_color,
        shininess, u_specular_strength
    );
    lit += u_emissive;
    return vec4(lit, base.a);
}
#endif
