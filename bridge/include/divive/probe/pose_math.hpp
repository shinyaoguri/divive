#pragma once

#include "divive/probe/model.hpp"

namespace divive::probe {

Vector3 position_from_matrix(const Matrix34& matrix) noexcept;
Quaternion quaternion_from_matrix(const Matrix34& matrix) noexcept;
bool same_pose(const Matrix34& lhs, const Matrix34& rhs,
               double epsilon = 1.0e-9) noexcept;

} // namespace divive::probe
