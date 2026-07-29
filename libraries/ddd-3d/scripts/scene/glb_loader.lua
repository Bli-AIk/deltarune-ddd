local LIB_ID = "ddd-3d"
local Math3D = libRequire(LIB_ID, "scripts.core.math3d")
local Node = libRequire(LIB_ID, "scripts.scene.node")
local Mesh = libRequire(LIB_ID, "scripts.scene.mesh")
local Material = libRequire(LIB_ID, "scripts.scene.material")

local GLBLoader = {}

local GLB_MAGIC = "glTF"
local GLB_VERSION = 2
local JSON_CHUNK = 0x4E4F534A
local BIN_CHUNK = 0x004E4942

local TYPE_COMPONENTS = {
    SCALAR = 1,
    VEC2 = 2,
    VEC3 = 3,
    VEC4 = 4,
}

local COMPONENTS = {
    [5120] = { size = 1, signed = true, maximum = 127, minimum = -128 },
    [5121] = { size = 1, signed = false, maximum = 255, minimum = 0 },
    [5122] = { size = 2, signed = true, maximum = 32767, minimum = -32768 },
    [5123] = { size = 2, signed = false, maximum = 65535, minimum = 0 },
    [5125] = { size = 4, signed = false, maximum = 4294967295, minimum = 0 },
    [5126] = { size = 4, float = true },
}

local Model = {}
Model.__index = Model

local function release_resources(meshes, materials)
    for _, mesh in ipairs(meshes or {}) do
        if mesh and mesh.release then
            pcall(mesh.release, mesh)
        end
    end
    for _, material in ipairs(materials or {}) do
        if material and material.release then
            pcall(material.release, material)
        end
    end
end

local function read_u8(data, offset)
    local byte = data:byte(offset + 1)
    if not byte then
        return nil, "unexpected end of binary data"
    end
    return byte
end

local function read_u16(data, offset)
    local a, err_a = read_u8(data, offset)
    local b, err_b = read_u8(data, offset + 1)
    if not a then return nil, err_a end
    if not b then return nil, err_b end
    return a + b * 256
end

local function read_u32(data, offset)
    local a, err_a = read_u8(data, offset)
    local b, err_b = read_u8(data, offset + 1)
    local c, err_c = read_u8(data, offset + 2)
    local d, err_d = read_u8(data, offset + 3)
    if not a then return nil, err_a end
    if not b then return nil, err_b end
    if not c then return nil, err_c end
    if not d then return nil, err_d end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function read_float32(data, offset)
    local bits, err = read_u32(data, offset)
    if not bits then
        return nil, err
    end
    local sign = bits >= 2147483648 and -1 or 1
    local exponent = math.floor(bits / 8388608) % 256
    local mantissa = bits % 8388608
    if exponent == 255 then
        return nil, "GLB contains a non-finite float"
    end
    if exponent == 0 then
        return sign * mantissa * 2 ^ -149
    end
    return sign * (1 + mantissa / 8388608) * 2 ^ (exponent - 127)
end

local function read_component(data, offset, component_type, normalized)
    local descriptor = COMPONENTS[component_type]
    if not descriptor then
        return nil, "unsupported glTF component type: " .. tostring(component_type)
    end
    local value, err
    if descriptor.float then
        value, err = read_float32(data, offset)
    elseif descriptor.size == 1 then
        value, err = read_u8(data, offset)
        if value and descriptor.signed and value >= 128 then
            value = value - 256
        end
    elseif descriptor.size == 2 then
        value, err = read_u16(data, offset)
        if value and descriptor.signed and value >= 32768 then
            value = value - 65536
        end
    elseif descriptor.size == 4 then
        value, err = read_u32(data, offset)
        if value and descriptor.signed and value >= 2147483648 then
            value = value - 4294967296
        end
    end
    if value == nil then
        return nil, err
    end
    if normalized and not descriptor.float then
        if descriptor.signed then
            value = math.max(-1, value / descriptor.maximum)
        else
            value = value / descriptor.maximum
        end
    end
    return value
end

local function decode_accessor(document, binary, accessor_index)
    local accessor = document.accessors and document.accessors[accessor_index + 1]
    if type(accessor) ~= "table" then
        return nil, "accessor " .. tostring(accessor_index) .. " is missing"
    end
    if accessor.sparse then
        return nil, "sparse accessors are not supported"
    end
    local component_count = TYPE_COMPONENTS[accessor.type]
    local component = COMPONENTS[accessor.componentType]
    if not component_count or not component then
        return nil, "accessor " .. tostring(accessor_index) .. " has an unsupported layout"
    end
    local count = tonumber(accessor.count)
    if not count or count < 0 or count % 1 ~= 0 then
        return nil, "accessor " .. tostring(accessor_index) .. " has an invalid count"
    end
    if accessor.bufferView == nil then
        local zero_values = {}
        for _ = 1, count do
            local value = {}
            for component_index = 1, component_count do
                value[component_index] = 0
            end
            zero_values[#zero_values + 1] = value
        end
        return zero_values
    end
    local view = document.bufferViews and document.bufferViews[accessor.bufferView + 1]
    if type(view) ~= "table" then
        return nil, "buffer view " .. tostring(accessor.bufferView) .. " is missing"
    end
    if (view.buffer or 0) ~= 0 then
        return nil, "external GLB buffers are not supported"
    end
    local element_size = component.size * component_count
    local stride = tonumber(view.byteStride) or element_size
    if stride < element_size then
        return nil, "accessor stride is smaller than its element size"
    end
    local start = (tonumber(view.byteOffset) or 0) + (tonumber(accessor.byteOffset) or 0)
    local end_offset = start + math.max(0, count - 1) * stride + element_size
    local view_end = (tonumber(view.byteOffset) or 0) + (tonumber(view.byteLength) or 0)
    if start < 0 or end_offset > view_end or end_offset > #binary then
        return nil, "accessor " .. tostring(accessor_index) .. " exceeds its buffer view"
    end
    local values = {}
    for item = 0, count - 1 do
        local value = {}
        local item_offset = start + item * stride
        for component_index = 0, component_count - 1 do
            local number, err = read_component(
                binary,
                item_offset + component_index * component.size,
                accessor.componentType,
                accessor.normalized == true
            )
            if number == nil then
                return nil, "accessor " .. tostring(accessor_index) .. ": " .. tostring(err)
            end
            value[component_index + 1] = number
        end
        values[#values + 1] = value
    end
    return values
end

local function generate_normals(positions, indices)
    local normals = {}
    for index = 1, #positions do
        normals[index] = { 0, 0, 0 }
    end
    local vertex_map = indices
    if not vertex_map then
        vertex_map = {}
        for index = 1, #positions do
            vertex_map[index] = index
        end
    end
    for index = 1, #vertex_map - 2, 3 do
        local a, b, c = vertex_map[index], vertex_map[index + 1], vertex_map[index + 2]
        local edge_a = Math3D.sub3(positions[b], positions[a])
        local edge_b = Math3D.sub3(positions[c], positions[a])
        local normal = Math3D.cross3(edge_a, edge_b)
        for _, vertex_index in ipairs({ a, b, c }) do
            normals[vertex_index] = Math3D.add3(normals[vertex_index], normal)
        end
    end
    for index, normal in ipairs(normals) do
        normals[index] = Math3D.normalize3(normal, { 0, 0, 1 })
    end
    return normals
end

local function override_option(override, snake_case, camel_case)
    if override[snake_case] ~= nil then
        return override[snake_case]
    end
    return override[camel_case]
end

local function override_texture_option(override, names)
    for _, name in ipairs(names) do
        if override[name] ~= nil then
            return override[name]
        end
    end
    return nil
end

local function build_materials(document, options)
    local materials = {}
    local source_materials = document.materials or {}
    local overrides = options.material_overrides or {}
    for index, source in ipairs(source_materials) do
        local pbr = source.pbrMetallicRoughness or {}
        local override = overrides[source.name] or overrides[index - 1] or {}
        local base_color = override_option(override, "base_color", "baseColor")
        local alpha_mode = override_option(override, "alpha_mode", "alphaMode")
        local alpha_cutoff = override_option(override, "alpha_cutoff", "alphaCutoff")
        local double_sided = override_option(override, "double_sided", "doubleSided")
        local material, err = Material.new({
            name = override.name or source.name or ("material_" .. (index - 1)),
            shader = override.shader or "lit",
            base_color = base_color or pbr.baseColorFactor or { 1, 1, 1, 1 },
            emissive = override.emissive or source.emissiveFactor or { 0, 0, 0 },
            metallic = override.metallic == nil and (pbr.metallicFactor or 0) or override.metallic,
            roughness = override.roughness == nil and (pbr.roughnessFactor or 1) or override.roughness,
            specular_strength = override_option(override, "specular_strength", "specularStrength"),
            ambient_reflection = override_option(override, "ambient_reflection", "ambientReflection"),
            normal_strength = override_texture_option(override, {
                "normal_strength", "normalStrength", "normal_scale", "normalScale",
            }),
            uv_scale = override_option(override, "uv_scale", "uvScale"),
            base_color_texture = override_texture_option(override, {
                "base_color_texture", "baseColorTexture", "albedo_texture", "albedoTexture",
                "base_color_map", "baseColorMap", "albedo_map", "albedoMap", "texture",
            }),
            normal_texture = override_texture_option(override, {
                "normal_texture", "normalTexture", "normal_map", "normalMap",
            }),
            roughness_texture = override_texture_option(override, {
                "roughness_texture", "roughnessTexture", "roughness_map", "roughnessMap",
            }),
            alpha_mode = alpha_mode or source.alphaMode or "OPAQUE",
            alpha_cutoff = alpha_cutoff or source.alphaCutoff,
            double_sided = double_sided == nil and source.doubleSided or double_sided,
        })
        if not material then
            release_resources(nil, materials)
            return nil, "material " .. tostring(index - 1) .. ": " .. tostring(err)
        end
        materials[index] = material
    end
    local fallback, fallback_err = Material.new({ name = "default" })
    if not fallback then
        release_resources(nil, materials)
        return nil, fallback_err
    end
    return materials, fallback
end

local function build_meshes(document, binary, materials, fallback_material, options)
    local mesh_groups = {}
    local all_meshes = {}
    for mesh_index, source_mesh in ipairs(document.meshes or {}) do
        local group = {}
        local primitives = source_mesh.primitives or {}
        if #primitives == 0 then
            release_resources(all_meshes)
            return nil, "mesh " .. tostring(mesh_index - 1) .. " has no primitives"
        end
        for primitive_index, primitive in ipairs(primitives) do
            if primitive.mode ~= nil and primitive.mode ~= 4 then
                release_resources(all_meshes)
                return nil, "mesh " .. tostring(mesh_index - 1) .. " primitive " .. tostring(primitive_index - 1) .. " is not TRIANGLES"
            end
            local attributes = primitive.attributes or {}
            if attributes.POSITION == nil then
                release_resources(all_meshes)
                return nil, "mesh " .. tostring(mesh_index - 1) .. " has no POSITION attribute"
            end
            local positions, position_err = decode_accessor(document, binary, attributes.POSITION)
            if not positions then
                release_resources(all_meshes)
                return nil, position_err
            end
            local indices
            if primitive.indices ~= nil then
                local raw_indices, index_err = decode_accessor(document, binary, primitive.indices)
                if not raw_indices then
                    release_resources(all_meshes)
                    return nil, index_err
                end
                indices = {}
                for index, value in ipairs(raw_indices) do
                    local vertex_index = value[1]
                    if vertex_index % 1 ~= 0 or vertex_index < 0 or vertex_index >= #positions then
                        release_resources(all_meshes)
                        return nil, "mesh index " .. tostring(index - 1) .. " is out of range"
                    end
                    indices[index] = vertex_index + 1
                end
            end
            local normals
            if attributes.NORMAL ~= nil then
                normals, position_err = decode_accessor(document, binary, attributes.NORMAL)
                if not normals then
                    release_resources(all_meshes)
                    return nil, position_err
                end
            else
                normals = generate_normals(positions, indices)
            end
            local texcoords
            if attributes.TEXCOORD_0 ~= nil then
                texcoords, position_err = decode_accessor(document, binary, attributes.TEXCOORD_0)
                if not texcoords then
                    release_resources(all_meshes)
                    return nil, position_err
                end
            else
                texcoords = {}
                for index = 1, #positions do
                    texcoords[index] = { 0, 0 }
                end
            end
            local tangents
            if attributes.TANGENT ~= nil then
                tangents, position_err = decode_accessor(document, binary, attributes.TANGENT)
                if not tangents then
                    release_resources(all_meshes)
                    return nil, position_err
                end
            end
            if #normals ~= #positions or #texcoords ~= #positions or (tangents and #tangents ~= #positions) then
                release_resources(all_meshes)
                return nil, "mesh " .. tostring(mesh_index - 1) .. " has mismatched vertex attributes"
            end
            if (indices and #indices % 3 ~= 0) or (not indices and #positions % 3 ~= 0) then
                release_resources(all_meshes)
                return nil, "mesh " .. tostring(mesh_index - 1) .. " triangle data is incomplete"
            end
            local vertices = {}
            for index, position in ipairs(positions) do
                local normal = normals[index]
                local texcoord = texcoords[index]
                local tangent = tangents and tangents[index]
                if #position ~= 3
                    or #normal ~= 3
                    or #texcoord < 2
                    or (tangent and #tangent ~= 4)
                then
                    release_resources(all_meshes)
                    return nil, "mesh " .. tostring(mesh_index - 1) .. " has an invalid vertex attribute type"
                end
                local vertex = {
                    position[1], position[2], position[3],
                    normal[1], normal[2], normal[3],
                    texcoord[1], texcoord[2],
                }
                if tangent then
                    vertex[9], vertex[10], vertex[11], vertex[12] = tangent[1], tangent[2], tangent[3], tangent[4]
                end
                vertices[index] = vertex
            end
            local material = primitive.material ~= nil and materials[primitive.material + 1] or fallback_material
            if not material then
                release_resources(all_meshes)
                return nil, "mesh " .. tostring(mesh_index - 1) .. " references a missing material"
            end
            local mesh, mesh_err = Mesh.new(vertices, indices, {
                material = material,
                name = source_mesh.name or ("mesh_" .. (mesh_index - 1)),
                usage = options.mesh_usage,
            })
            if not mesh then
                release_resources(all_meshes)
                return nil, mesh_err
            end
            group[#group + 1] = mesh
            all_meshes[#all_meshes + 1] = mesh
        end
        mesh_groups[mesh_index] = group
    end
    return mesh_groups, all_meshes
end

local function node_options(source)
    local options = {
        name = source.name,
        position = source.translation,
        rotation = source.rotation,
        scale = source.scale,
    }
    if source.matrix then
        options.matrix = source.matrix
    end
    return options
end

local function build_nodes(document, mesh_groups)
    local source_nodes = document.nodes or {}
    local nodes_by_index = {}
    local nodes_by_name = {}
    local visiting = {}

    local function build(index)
        if nodes_by_index[index + 1] then
            return nodes_by_index[index + 1]
        end
        if visiting[index + 1] then
            return nil, "GLB node hierarchy contains a cycle"
        end
        local source = source_nodes[index + 1]
        if type(source) ~= "table" then
            return nil, "scene references a missing node " .. tostring(index)
        end
        visiting[index + 1] = true
        local node = Node.new(node_options(source))
        nodes_by_index[index + 1] = node
        if source.name then
            local named_nodes = nodes_by_name[source.name]
            if not named_nodes then
                named_nodes = {}
                nodes_by_name[source.name] = named_nodes
            end
            named_nodes[#named_nodes + 1] = node
        end
        if source.mesh ~= nil then
            local primitives = mesh_groups[source.mesh + 1]
            if not primitives then
                return nil, "node " .. tostring(index) .. " references a missing mesh"
            end
            if #primitives == 1 then
                node.mesh = primitives[1]
                node.material = primitives[1].material
            else
                for primitive_index, mesh in ipairs(primitives) do
                    local primitive_node = Node.new({
                        name = (node.name or "mesh") .. "_primitive_" .. tostring(primitive_index - 1),
                        mesh = mesh,
                        material = mesh.material,
                    })
                    local added, add_err = node:addChild(primitive_node)
                    if not added then
                        return nil, add_err
                    end
                end
            end
        end
        for _, child_index in ipairs(source.children or {}) do
            local child, child_err = build(child_index)
            if not child then
                return nil, child_err
            end
            local added, add_err = node:addChild(child)
            if not added then
                return nil, add_err
            end
        end
        visiting[index + 1] = nil
        return node
    end

    local root = Node.new({ name = "root" })
    local scene = document.scenes and document.scenes[(document.scene or 0) + 1]
    local root_indices = scene and scene.nodes or nil
    if not root_indices then
        root_indices = {}
        for index = 0, #source_nodes - 1 do
            root_indices[#root_indices + 1] = index
        end
    end
    for _, index in ipairs(root_indices) do
        local node, err = build(index)
        if not node then
            return nil, err
        end
        local added, add_err = root:addChild(node)
        if not added then
            return nil, add_err
        end
    end
    return root, nodes_by_index, nodes_by_name
end

function Model:findNodes(name)
    if type(name) == "number" then
        local indexed = self.nodes_by_index[name + 1]
        return indexed and { indexed } or {}
    end
    if type(name) ~= "string" then
        return {}
    end
    return self.nodes_by_name[name] or {}
end

function Model:findNode(name)
    local nodes = self:findNodes(name)
    return nodes[1]
end

--- Returns a named source node only when the GLB has exactly one match.
function Model:requireUniqueNode(name)
    if type(name) ~= "string" or name == "" then
        return nil, "node name must be a non-empty string"
    end
    local nodes = self:findNodes(name)
    if #nodes == 0 then
        return nil, "model has no node named " .. name
    end
    if #nodes > 1 then
        return nil, "model has duplicate nodes named " .. name
    end
    return nodes[1]
end

function Model:requireUniqueMaterial(name)
    if type(name) ~= "string" or name == "" then
        return nil, "material name must be a non-empty string"
    end
    local count = self.source_material_names[name] or 0
    if count == 0 then
        return nil, "model has no material named " .. name
    end
    if count > 1 then
        return nil, "model has duplicate materials named " .. name
    end
    return true
end

local function apply_instance_options(instance, options)
    if options.position then instance:setPosition(options.position) end
    if options.rotation then instance:setRotation(options.rotation) end
    if options.scale then instance:setScale(options.scale) end
    if options.matrix then
        local set, set_err = instance:setMatrix(options.matrix)
        if not set then return nil, set_err end
    end
    if options.name then instance.name = options.name end
    if options.visible ~= nil then instance.visible = options.visible end
    if options.enabled ~= nil then instance.enabled = options.enabled end
    if options.onUpdate then instance.onUpdate = options.onUpdate end
    if options.material then
        instance:traverse(function(node)
            if node.mesh then
                node.material = options.material
            end
        end)
    end
    return instance
end

--- Clones the full model or a named source node without duplicating GPU meshes.
function Model:instantiate(options)
    if self.released then
        return nil, "model has been released"
    end
    options = options or {}
    if type(options) ~= "table" then
        return nil, "model instantiate options must be a table"
    end
    local source = self.root
    if options.node ~= nil then
        if type(options.node) == "string" then
            local node_err
            source, node_err = self:requireUniqueNode(options.node)
            if not source then
                return nil, node_err
            end
        else
            source = self:findNode(options.node)
            if not source then
                return nil, "model has no node at index " .. tostring(options.node)
            end
        end
    end
    local instance = source:clone({})
    return apply_instance_options(instance, options)
end

function Model:release()
    if self.released then
        return true
    end
    release_resources(self.meshes, self.materials)
    if self.fallback_material and self.fallback_material.release then
        pcall(self.fallback_material.release, self.fallback_material)
    end
    self.released = true
    return true
end

local function parse_glb(data)
    if type(data) ~= "string" or #data < 20 then
        return nil, "file is not a complete GLB 2.0 payload"
    end
    if data:sub(1, 4) ~= GLB_MAGIC then
        return nil, "file does not start with the GLB magic"
    end
    local version, version_err = read_u32(data, 4)
    local length, length_err = read_u32(data, 8)
    if not version then return nil, version_err end
    if not length then return nil, length_err end
    if version ~= GLB_VERSION then
        return nil, "unsupported GLB version " .. tostring(version)
    end
    if length > #data or length < 20 then
        return nil, "GLB header has an invalid total length"
    end
    local offset = 12
    local json_chunk
    local binary_chunk
    while offset < length do
        local chunk_length, chunk_length_err = read_u32(data, offset)
        local chunk_type, chunk_type_err = read_u32(data, offset + 4)
        if not chunk_length then return nil, chunk_length_err end
        if not chunk_type then return nil, chunk_type_err end
        offset = offset + 8
        if offset + chunk_length > length then
            return nil, "GLB chunk exceeds the declared file length"
        end
        local chunk = data:sub(offset + 1, offset + chunk_length)
        if chunk_type == JSON_CHUNK then
            json_chunk = chunk
        elseif chunk_type == BIN_CHUNK then
            binary_chunk = chunk
        end
        offset = offset + chunk_length
    end
    if not json_chunk then
        return nil, "GLB has no JSON chunk"
    end
    if not binary_chunk then
        return nil, "GLB has no binary chunk"
    end
    local decoder = rawget(_G, "JSON") or rawget(_G, "json")
    if type(decoder) ~= "table" or type(decoder.decode) ~= "function" then
        return nil, "a JSON decoder (Kristal's JSON) is required to load GLB files"
    end
    local decoded, document = pcall(decoder.decode, json_chunk)
    if not decoded or type(document) ~= "table" then
        return nil, "could not decode GLB JSON: " .. tostring(document)
    end
    if not document.asset or tostring(document.asset.version):sub(1, 1) ~= "2" then
        return nil, "GLB JSON is not glTF 2.0"
    end
    return document, binary_chunk
end

function GLBLoader.loadData(data, options)
    options = options or {}
    if type(options) ~= "table" then
        return nil, "GLB loader options must be a table"
    end
    local ok, model_or_err, model_err = xpcall(function()
        local document, binary_or_err = parse_glb(data)
        if not document then
            return nil, binary_or_err
        end
        local binary = binary_or_err
        local materials, fallback_or_err = build_materials(document, options)
        if not materials then
            return nil, fallback_or_err
        end
        local fallback_material = fallback_or_err
        local mesh_groups, meshes_or_err = build_meshes(document, binary, materials, fallback_material, options)
        if not mesh_groups then
            release_resources(nil, materials)
            fallback_material:release()
            return nil, meshes_or_err
        end
        local meshes = meshes_or_err
        local root, nodes_by_index, nodes_by_name = build_nodes(document, mesh_groups)
        if not root then
            release_resources(meshes, materials)
            fallback_material:release()
            return nil, nodes_by_index
        end
        local source_material_names = {}
        for _, material in ipairs(document.materials or {}) do
            if type(material.name) == "string" and material.name ~= "" then
                source_material_names[material.name] = (source_material_names[material.name] or 0) + 1
            end
        end
        return setmetatable({
            root = root,
            nodes_by_index = nodes_by_index,
            nodes_by_name = nodes_by_name,
            source_material_names = source_material_names,
            meshes = meshes,
            materials = materials,
            fallback_material = fallback_material,
            source = options.source,
            released = false,
        }, Model)
    end, function(err)
        return tostring(err)
    end)
    if not ok then
        return nil, "could not load GLB: " .. tostring(model_or_err)
    end
    if not model_or_err then
        return nil, model_err
    end
    return model_or_err
end

local function read_file(path)
    if type(path) ~= "string" or path == "" then
        return nil, "GLB path must be a non-empty string"
    end
    if love and love.filesystem and love.filesystem.read then
        local ok, data, read_err = pcall(love.filesystem.read, path)
        if ok and type(data) == "string" then
            return data
        end
        if not ok then
            read_err = data
        end
        if read_err then
            -- Keep trying io.open in development, where absolute paths are useful.
        end
    end
    if io and io.open then
        local opened, file_or_err = pcall(io.open, path, "rb")
        if opened and file_or_err then
            local file = file_or_err
            local read_ok, data = pcall(file.read, file, "*a")
            pcall(file.close, file)
            if read_ok and type(data) == "string" then
                return data
            end
            return nil, "could not read GLB file: " .. tostring(data)
        end
    end
    return nil, "could not read GLB file: " .. path
end

function GLBLoader.load(path, options)
    local data, err = read_file(path)
    if not data then
        return nil, err
    end
    if options ~= nil and type(options) ~= "table" then
        return nil, "GLB loader options must be a table"
    end
    local load_options = {}
    for key, value in pairs(options or {}) do
        load_options[key] = value
    end
    load_options.source = load_options.source or path
    return GLBLoader.loadData(data, load_options)
end

GLBLoader.Model = Model

return GLBLoader
