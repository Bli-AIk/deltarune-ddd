local Math3D = {}

local EPSILON = 0.000001

function Math3D.vec3(x, y, z)
    return { x or 0, y or 0, z or 0 }
end

function Math3D.copy3(value, fallback)
    value = value or fallback or { 0, 0, 0 }
    return { value[1] or 0, value[2] or 0, value[3] or 0 }
end

function Math3D.add3(a, b)
    return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

function Math3D.sub3(a, b)
    return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

function Math3D.scale3(value, scale)
    return { value[1] * scale, value[2] * scale, value[3] * scale }
end

function Math3D.dot3(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

function Math3D.cross3(a, b)
    return {
        a[2] * b[3] - a[3] * b[2],
        a[3] * b[1] - a[1] * b[3],
        a[1] * b[2] - a[2] * b[1],
    }
end

function Math3D.length3(value)
    return math.sqrt(Math3D.dot3(value, value))
end

function Math3D.normalize3(value, fallback)
    local length = Math3D.length3(value)
    if length <= EPSILON then
        return Math3D.copy3(fallback, { 0, 0, 0 })
    end
    return { value[1] / length, value[2] / length, value[3] / length }
end

function Math3D.quat(x, y, z, w)
    return { x or 0, y or 0, z or 0, w == nil and 1 or w }
end

function Math3D.copyQuat(value)
    value = value or { 0, 0, 0, 1 }
    return { value[1] or 0, value[2] or 0, value[3] or 0, value[4] == nil and 1 or value[4] }
end

function Math3D.normalizeQuat(value)
    local x, y, z, w = value[1], value[2], value[3], value[4]
    local length = math.sqrt(x * x + y * y + z * z + w * w)
    if length <= EPSILON then
        return { 0, 0, 0, 1 }
    end
    return { x / length, y / length, z / length, w / length }
end

--- Euler angles are radians and applied in X/Y/Z order.
function Math3D.quatFromEuler(x, y, z)
    x, y, z = (x or 0) * 0.5, (y or 0) * 0.5, (z or 0) * 0.5
    local sx, cx = math.sin(x), math.cos(x)
    local sy, cy = math.sin(y), math.cos(y)
    local sz, cz = math.sin(z), math.cos(z)
    return Math3D.normalizeQuat({
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    })
end

function Math3D.quatFromAxisAngle(axis, angle)
    local normalized = Math3D.normalize3(axis or { 0, 1, 0 }, { 0, 1, 0 })
    local half_angle = (angle or 0) * 0.5
    local sine = math.sin(half_angle)
    return {
        normalized[1] * sine,
        normalized[2] * sine,
        normalized[3] * sine,
        math.cos(half_angle),
    }
end

function Math3D.multiplyQuat(a, b)
    return Math3D.normalizeQuat({
        a[4] * b[1] + a[1] * b[4] + a[2] * b[3] - a[3] * b[2],
        a[4] * b[2] - a[1] * b[3] + a[2] * b[4] + a[3] * b[1],
        a[4] * b[3] + a[1] * b[2] - a[2] * b[1] + a[3] * b[4],
        a[4] * b[4] - a[1] * b[1] - a[2] * b[2] - a[3] * b[3],
    })
end

function Math3D.mat4Identity()
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
    }
end

function Math3D.copyMat4(matrix)
    local copy = {}
    for index = 1, 16 do
        copy[index] = matrix[index] or 0
    end
    return copy
end

--- Multiplies column-major matrices (a * b).
function Math3D.multiplyMat4(a, b)
    local output = {}
    for column = 0, 3 do
        for row = 0, 3 do
            local index = column * 4 + row + 1
            output[index] =
                a[row + 1] * b[column * 4 + 1] +
                a[4 + row + 1] * b[column * 4 + 2] +
                a[8 + row + 1] * b[column * 4 + 3] +
                a[12 + row + 1] * b[column * 4 + 4]
        end
    end
    return output
end

function Math3D.mat4FromTRS(position, rotation, scale)
    position = position or { 0, 0, 0 }
    rotation = Math3D.normalizeQuat(rotation or { 0, 0, 0, 1 })
    scale = scale or { 1, 1, 1 }

    local x, y, z, w = rotation[1], rotation[2], rotation[3], rotation[4]
    local x2, y2, z2 = x + x, y + y, z + z
    local xx, xy, xz = x * x2, x * y2, x * z2
    local yy, yz, zz = y * y2, y * z2, z * z2
    local wx, wy, wz = w * x2, w * y2, w * z2
    local sx, sy, sz = scale[1] or 1, scale[2] or 1, scale[3] or 1

    return {
        (1 - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0,
        (xy - wz) * sy, (1 - (xx + zz)) * sy, (yz + wx) * sy, 0,
        (xz + wy) * sz, (yz - wx) * sz, (1 - (xx + yy)) * sz, 0,
        position[1] or 0, position[2] or 0, position[3] or 0, 1,
    }
end

function Math3D.transformPoint(matrix, point)
    local x, y, z = point[1], point[2], point[3]
    local w = matrix[4] * x + matrix[8] * y + matrix[12] * z + matrix[16]
    if math.abs(w) <= EPSILON then
        w = 1
    end
    return {
        (matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13]) / w,
        (matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14]) / w,
        (matrix[3] * x + matrix[7] * y + matrix[11] * z + matrix[15]) / w,
    }
end

function Math3D.transformDirection(matrix, direction)
    local x, y, z = direction[1], direction[2], direction[3]
    return {
        matrix[1] * x + matrix[5] * y + matrix[9] * z,
        matrix[2] * x + matrix[6] * y + matrix[10] * z,
        matrix[3] * x + matrix[7] * y + matrix[11] * z,
    }
end

function Math3D.perspective(fov, aspect, near, far)
    near = near or 0.1
    far = far or 1000
    aspect = aspect or 1
    if near <= 0 or far <= near or aspect <= 0 then
        return nil, "invalid perspective parameters"
    end
    local focal_length = 1 / math.tan((fov or math.rad(50)) * 0.5)
    local range_inverse = 1 / (near - far)
    return {
        focal_length / aspect, 0, 0, 0,
        0, focal_length, 0, 0,
        0, 0, (far + near) * range_inverse, -1,
        0, 0, 2 * far * near * range_inverse, 0,
    }
end

function Math3D.lookAt(eye, target, up)
    up = up or { 0, 1, 0 }
    local forward = Math3D.normalize3(Math3D.sub3(eye, target), { 0, 0, 1 })
    local right = Math3D.normalize3(Math3D.cross3(up, forward), { 1, 0, 0 })
    local corrected_up = Math3D.cross3(forward, right)

    return {
        right[1], corrected_up[1], forward[1], 0,
        right[2], corrected_up[2], forward[2], 0,
        right[3], corrected_up[3], forward[3], 0,
        -Math3D.dot3(right, eye), -Math3D.dot3(corrected_up, eye), -Math3D.dot3(forward, eye), 1,
    }
end

function Math3D.invertMat4(matrix)
    local a00, a01, a02, a03 = matrix[1], matrix[2], matrix[3], matrix[4]
    local a10, a11, a12, a13 = matrix[5], matrix[6], matrix[7], matrix[8]
    local a20, a21, a22, a23 = matrix[9], matrix[10], matrix[11], matrix[12]
    local a30, a31, a32, a33 = matrix[13], matrix[14], matrix[15], matrix[16]
    local b00 = a00 * a11 - a01 * a10
    local b01 = a00 * a12 - a02 * a10
    local b02 = a00 * a13 - a03 * a10
    local b03 = a01 * a12 - a02 * a11
    local b04 = a01 * a13 - a03 * a11
    local b05 = a02 * a13 - a03 * a12
    local b06 = a20 * a31 - a21 * a30
    local b07 = a20 * a32 - a22 * a30
    local b08 = a20 * a33 - a23 * a30
    local b09 = a21 * a32 - a22 * a31
    local b10 = a21 * a33 - a23 * a31
    local b11 = a22 * a33 - a23 * a32
    local determinant = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06
    if math.abs(determinant) <= EPSILON then
        return nil, "matrix is not invertible"
    end
    determinant = 1 / determinant
    return {
        (a11 * b11 - a12 * b10 + a13 * b09) * determinant,
        (a02 * b10 - a01 * b11 - a03 * b09) * determinant,
        (a31 * b05 - a32 * b04 + a33 * b03) * determinant,
        (a22 * b04 - a21 * b05 - a23 * b03) * determinant,
        (a12 * b08 - a10 * b11 - a13 * b07) * determinant,
        (a00 * b11 - a02 * b08 + a03 * b07) * determinant,
        (a32 * b02 - a30 * b05 - a33 * b01) * determinant,
        (a20 * b05 - a22 * b02 + a23 * b01) * determinant,
        (a10 * b10 - a11 * b08 + a13 * b06) * determinant,
        (a01 * b08 - a00 * b10 - a03 * b06) * determinant,
        (a30 * b04 - a31 * b02 + a33 * b00) * determinant,
        (a21 * b02 - a20 * b04 - a23 * b00) * determinant,
        (a11 * b07 - a10 * b09 - a12 * b06) * determinant,
        (a00 * b09 - a01 * b07 + a02 * b06) * determinant,
        (a31 * b01 - a30 * b03 - a32 * b00) * determinant,
        (a20 * b03 - a21 * b01 + a22 * b00) * determinant,
    }
end

--- Returns the inverse-transpose of the upper-left 3x3 in column-major order.
function Math3D.normalMatrixFromMat4(matrix)
    local a00, a01, a02 = matrix[1], matrix[5], matrix[9]
    local a10, a11, a12 = matrix[2], matrix[6], matrix[10]
    local a20, a21, a22 = matrix[3], matrix[7], matrix[11]
    local c00 = a11 * a22 - a12 * a21
    local c01 = a12 * a20 - a10 * a22
    local c02 = a10 * a21 - a11 * a20
    local c10 = a02 * a21 - a01 * a22
    local c11 = a00 * a22 - a02 * a20
    local c12 = a01 * a20 - a00 * a21
    local c20 = a01 * a12 - a02 * a11
    local c21 = a02 * a10 - a00 * a12
    local c22 = a00 * a11 - a01 * a10
    local determinant = a00 * c00 + a01 * c01 + a02 * c02
    if math.abs(determinant) <= EPSILON then
        return {
            1, 0, 0,
            0, 1, 0,
            0, 0, 1,
        }
    end
    local inverse_determinant = 1 / determinant
    return {
        c00 * inverse_determinant, c10 * inverse_determinant, c20 * inverse_determinant,
        c01 * inverse_determinant, c11 * inverse_determinant, c21 * inverse_determinant,
        c02 * inverse_determinant, c12 * inverse_determinant, c22 * inverse_determinant,
    }
end

return Math3D
