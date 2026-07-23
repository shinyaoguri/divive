#include "divive/probe/pose_math.hpp"

#include <algorithm>
#include <cmath>

namespace divive::probe {

Vector3 position_from_matrix(const Matrix34& matrix) noexcept {
    return Vector3{
        .x = matrix.values[3],
        .y = matrix.values[7],
        .z = matrix.values[11],
    };
}

Quaternion quaternion_from_matrix(const Matrix34& matrix) noexcept {
    const double m00 = matrix.values[0];
    const double m01 = matrix.values[1];
    const double m02 = matrix.values[2];
    const double m10 = matrix.values[4];
    const double m11 = matrix.values[5];
    const double m12 = matrix.values[6];
    const double m20 = matrix.values[8];
    const double m21 = matrix.values[9];
    const double m22 = matrix.values[10];

    Quaternion result;
    const double trace = m00 + m11 + m22;
    if (trace > 0.0) {
        const double scale = std::sqrt(trace + 1.0) * 2.0;
        result.w = 0.25 * scale;
        result.x = (m21 - m12) / scale;
        result.y = (m02 - m20) / scale;
        result.z = (m10 - m01) / scale;
    } else if (m00 > m11 && m00 > m22) {
        const double scale = std::sqrt(1.0 + m00 - m11 - m22) * 2.0;
        result.w = (m21 - m12) / scale;
        result.x = 0.25 * scale;
        result.y = (m01 + m10) / scale;
        result.z = (m02 + m20) / scale;
    } else if (m11 > m22) {
        const double scale = std::sqrt(1.0 + m11 - m00 - m22) * 2.0;
        result.w = (m02 - m20) / scale;
        result.x = (m01 + m10) / scale;
        result.y = 0.25 * scale;
        result.z = (m12 + m21) / scale;
    } else {
        const double scale = std::sqrt(1.0 + m22 - m00 - m11) * 2.0;
        result.w = (m10 - m01) / scale;
        result.x = (m02 + m20) / scale;
        result.y = (m12 + m21) / scale;
        result.z = 0.25 * scale;
    }

    const double length = std::sqrt(result.x * result.x + result.y * result.y +
                                    result.z * result.z + result.w * result.w);
    if (!std::isfinite(length) || length < 1.0e-12) {
        return Quaternion{};
    }

    result.x /= length;
    result.y /= length;
    result.z /= length;
    result.w /= length;
    return result;
}

bool same_pose(const Matrix34& lhs, const Matrix34& rhs,
               const double epsilon) noexcept {
    return std::equal(lhs.values.begin(), lhs.values.end(), rhs.values.begin(),
                      [epsilon](const double left, const double right) {
                          return std::abs(left - right) <= epsilon;
                      });
}

} // namespace divive::probe
