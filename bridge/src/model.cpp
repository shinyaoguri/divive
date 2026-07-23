#include "divive/probe/model.hpp"

namespace divive::probe {

std::string_view to_string(const Origin value) noexcept {
    switch (value) {
    case Origin::standing:
        return "standing";
    case Origin::seated:
        return "seated";
    case Origin::raw:
        return "raw";
    }
    return "unknown";
}

std::string_view to_string(const DeviceClass value) noexcept {
    switch (value) {
    case DeviceClass::invalid:
        return "invalid";
    case DeviceClass::hmd:
        return "hmd";
    case DeviceClass::controller:
        return "controller";
    case DeviceClass::generic_tracker:
        return "generic_tracker";
    case DeviceClass::tracking_reference:
        return "tracking_reference";
    case DeviceClass::display_redirect:
        return "display_redirect";
    case DeviceClass::unknown:
        return "unknown";
    }
    return "unknown";
}

std::string_view to_string(const TrackingResult value) noexcept {
    switch (value) {
    case TrackingResult::uninitialized:
        return "uninitialized";
    case TrackingResult::calibrating_in_progress:
        return "calibrating_in_progress";
    case TrackingResult::calibrating_out_of_range:
        return "calibrating_out_of_range";
    case TrackingResult::running_ok:
        return "running_ok";
    case TrackingResult::running_out_of_range:
        return "running_out_of_range";
    case TrackingResult::fallback_rotation_only:
        return "fallback_rotation_only";
    case TrackingResult::unknown:
        return "unknown";
    }
    return "unknown";
}

} // namespace divive::probe
