#include "openvr_session.hpp"

#include "divive/probe/pose_math.hpp"

#include <openvr.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>

namespace divive::probe {
namespace {

DeviceClass convert_device_class(const vr::ETrackedDeviceClass value) {
    switch (value) {
    case vr::TrackedDeviceClass_Invalid:
        return DeviceClass::invalid;
    case vr::TrackedDeviceClass_HMD:
        return DeviceClass::hmd;
    case vr::TrackedDeviceClass_Controller:
        return DeviceClass::controller;
    case vr::TrackedDeviceClass_GenericTracker:
        return DeviceClass::generic_tracker;
    case vr::TrackedDeviceClass_TrackingReference:
        return DeviceClass::tracking_reference;
    case vr::TrackedDeviceClass_DisplayRedirect:
        return DeviceClass::display_redirect;
    default:
        return DeviceClass::unknown;
    }
}

TrackingResult convert_tracking_result(const vr::ETrackingResult value) {
    switch (value) {
    case vr::TrackingResult_Uninitialized:
        return TrackingResult::uninitialized;
    case vr::TrackingResult_Calibrating_InProgress:
        return TrackingResult::calibrating_in_progress;
    case vr::TrackingResult_Calibrating_OutOfRange:
        return TrackingResult::calibrating_out_of_range;
    case vr::TrackingResult_Running_OK:
        return TrackingResult::running_ok;
    case vr::TrackingResult_Running_OutOfRange:
        return TrackingResult::running_out_of_range;
    case vr::TrackingResult_Fallback_RotationOnly:
        return TrackingResult::fallback_rotation_only;
    default:
        return TrackingResult::unknown;
    }
}

vr::ETrackingUniverseOrigin convert_origin(const Origin value) {
    switch (value) {
    case Origin::standing:
        return vr::TrackingUniverseStanding;
    case Origin::seated:
        return vr::TrackingUniverseSeated;
    case Origin::raw:
        return vr::TrackingUniverseRawAndUncalibrated;
    }
    return vr::TrackingUniverseStanding;
}

std::string property_error(vr::IVRSystem* system,
                           const vr::ETrackedPropertyError error) {
    const char* name = system->GetPropErrorNameFromEnum(error);
    return name == nullptr ? "TrackedProp_Unknown" : std::string(name);
}

PropertyValue<std::string> string_property(vr::IVRSystem* system,
                                           const vr::TrackedDeviceIndex_t index,
                                           const vr::ETrackedDeviceProperty property) {
    std::array<char, vr::k_unMaxPropertyStringSize> buffer{};
    vr::ETrackedPropertyError error = vr::TrackedProp_Success;
    const auto length = system->GetStringTrackedDeviceProperty(
        index, property, buffer.data(), static_cast<std::uint32_t>(buffer.size()),
        &error);

    PropertyValue<std::string> result;
    result.error = property_error(system, error);
    if (error == vr::TrackedProp_Success && length > 0) {
        result.value = std::string(buffer.data());
    }
    return result;
}

PropertyValue<bool> bool_property(vr::IVRSystem* system,
                                  const vr::TrackedDeviceIndex_t index,
                                  const vr::ETrackedDeviceProperty property) {
    vr::ETrackedPropertyError error = vr::TrackedProp_Success;
    const bool value = system->GetBoolTrackedDeviceProperty(index, property, &error);

    PropertyValue<bool> result;
    result.error = property_error(system, error);
    if (error == vr::TrackedProp_Success) {
        result.value = value;
    }
    return result;
}

PropertyValue<double> float_property(vr::IVRSystem* system,
                                     const vr::TrackedDeviceIndex_t index,
                                     const vr::ETrackedDeviceProperty property) {
    vr::ETrackedPropertyError error = vr::TrackedProp_Success;
    const float value = system->GetFloatTrackedDeviceProperty(index, property, &error);

    PropertyValue<double> result;
    result.error = property_error(system, error);
    if (error == vr::TrackedProp_Success) {
        result.value = static_cast<double>(value);
    }
    return result;
}

Matrix34 convert_matrix(const vr::HmdMatrix34_t& source) {
    Matrix34 result;
    std::size_t destination = 0;
    for (std::size_t row = 0; row < 3; ++row) {
        for (std::size_t column = 0; column < 4; ++column) {
            result.values[destination++] = static_cast<double>(source.m[row][column]);
        }
    }
    return result;
}

Vector3 convert_vector(const vr::HmdVector3_t& source) {
    return Vector3{
        .x = static_cast<double>(source.v[0]),
        .y = static_cast<double>(source.v[1]),
        .z = static_cast<double>(source.v[2]),
    };
}

bool should_include(const vr::ETrackedDeviceClass device_class,
                    const bool trackers_only) {
    if (device_class == vr::TrackedDeviceClass_Invalid) {
        return false;
    }
    return !trackers_only || device_class == vr::TrackedDeviceClass_GenericTracker;
}

} // namespace

std::unique_ptr<OpenVrSession> OpenVrSession::create(std::string& error) {
    if (!vr::VR_IsRuntimeInstalled()) {
        error = "OpenVR runtimeがインストールされていません";
        return nullptr;
    }

    vr::EVRInitError init_error = vr::VRInitError_None;
    vr::IVRSystem* system = vr::VR_Init(&init_error, vr::VRApplication_Background);
    if (system == nullptr || init_error != vr::VRInitError_None) {
        const char* description = vr::VR_GetVRInitErrorAsEnglishDescription(init_error);
        error = description == nullptr ? "OpenVR runtimeへ接続できません"
                                       : std::string(description);
        return nullptr;
    }

    return std::unique_ptr<OpenVrSession>(new OpenVrSession(system));
}

OpenVrSession::OpenVrSession(vr::IVRSystem* system) : system_(system) {}

OpenVrSession::~OpenVrSession() {
    if (system_ != nullptr) {
        vr::VR_Shutdown();
        system_ = nullptr;
    }
}

std::string OpenVrSession::sdk_version() const {
    return std::to_string(vr::k_nSteamVRVersionMajor) + "." +
           std::to_string(vr::k_nSteamVRVersionMinor) + "." +
           std::to_string(vr::k_nSteamVRVersionBuild);
}

std::string OpenVrSession::runtime_path() const {
    std::array<char, vr::k_unMaxPropertyStringSize> buffer{};
    std::uint32_t required_size = 0;
    const bool success = vr::VR_GetRuntimePath(
        buffer.data(), static_cast<std::uint32_t>(buffer.size()), &required_size);
    if (!success || required_size == 0 || required_size > buffer.size()) {
        return {};
    }
    return std::string(buffer.data());
}

std::vector<DeviceInventory> OpenVrSession::inventory(const bool trackers_only) {
    std::vector<DeviceInventory> result;
    result.reserve(vr::k_unMaxTrackedDeviceCount);

    for (vr::TrackedDeviceIndex_t index = 0; index < vr::k_unMaxTrackedDeviceCount;
         ++index) {
        const auto openvr_class = system_->GetTrackedDeviceClass(index);
        if (!should_include(openvr_class, trackers_only)) {
            serial_by_index_[index].clear();
            continue;
        }

        DeviceInventory device;
        device.device_index = index;
        device.device_class = convert_device_class(openvr_class);
        device.connected = system_->IsTrackedDeviceConnected(index);
        device.serial = string_property(system_, index, vr::Prop_SerialNumber_String);
        device.manufacturer =
            string_property(system_, index, vr::Prop_ManufacturerName_String);
        device.model = string_property(system_, index, vr::Prop_ModelNumber_String);
        device.tracking_system =
            string_property(system_, index, vr::Prop_TrackingSystemName_String);
        device.firmware =
            string_property(system_, index, vr::Prop_TrackingFirmwareVersion_String);
        device.controller_type =
            string_property(system_, index, vr::Prop_ControllerType_String);
        device.connected_dongle =
            string_property(system_, index, vr::Prop_ConnectedWirelessDongle_String);
        device.wireless = bool_property(system_, index, vr::Prop_DeviceIsWireless_Bool);
        device.provides_battery =
            bool_property(system_, index, vr::Prop_DeviceProvidesBatteryStatus_Bool);
        device.battery =
            float_property(system_, index, vr::Prop_DeviceBatteryPercentage_Float);
        device.charging = bool_property(system_, index, vr::Prop_DeviceIsCharging_Bool);

        serial_by_index_[index] = device.serial.value.value_or(std::string{});
        result.push_back(std::move(device));
    }

    return result;
}

PoseFrame OpenVrSession::sample(const std::uint64_t sequence,
                                const std::uint64_t elapsed_ns, const Origin origin,
                                const double prediction_seconds,
                                const bool trackers_only) {
    std::array<vr::TrackedDevicePose_t, vr::k_unMaxTrackedDeviceCount> poses{};
    system_->GetDeviceToAbsoluteTrackingPose(
        convert_origin(origin), static_cast<float>(prediction_seconds), poses.data(),
        static_cast<std::uint32_t>(poses.size()));

    PoseFrame frame;
    frame.sequence = sequence;
    frame.elapsed_ns = elapsed_ns;
    frame.devices.reserve(vr::k_unMaxTrackedDeviceCount);

    for (vr::TrackedDeviceIndex_t index = 0; index < vr::k_unMaxTrackedDeviceCount;
         ++index) {
        const auto openvr_class = system_->GetTrackedDeviceClass(index);
        if (!should_include(openvr_class, trackers_only)) {
            continue;
        }

        const auto& source = poses[index];
        PoseSample sample;
        sample.device_index = index;
        sample.serial = serial_by_index_[index];
        sample.device_class = convert_device_class(openvr_class);
        sample.connected = source.bDeviceIsConnected;
        sample.pose_valid = source.bPoseIsValid;
        sample.tracking_result = convert_tracking_result(source.eTrackingResult);
        sample.matrix = convert_matrix(source.mDeviceToAbsoluteTracking);
        sample.position = position_from_matrix(sample.matrix);
        sample.orientation = quaternion_from_matrix(sample.matrix);
        sample.linear_velocity = convert_vector(source.vVelocity);
        sample.angular_velocity = convert_vector(source.vAngularVelocity);
        frame.devices.push_back(std::move(sample));
    }

    return frame;
}

} // namespace divive::probe
