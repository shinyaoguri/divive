#pragma once

#include "divive/probe/model.hpp"

#include <array>
#include <memory>
#include <string>
#include <vector>

namespace vr {
class IVRSystem;
}

namespace divive::probe {

class OpenVrSession {
  public:
    static std::unique_ptr<OpenVrSession> create(std::string& error);

    ~OpenVrSession();

    OpenVrSession(const OpenVrSession&) = delete;
    OpenVrSession& operator=(const OpenVrSession&) = delete;
    OpenVrSession(OpenVrSession&&) = delete;
    OpenVrSession& operator=(OpenVrSession&&) = delete;

    std::string sdk_version() const;
    std::string runtime_path() const;

    std::vector<DeviceInventory> inventory(bool trackers_only);
    PoseFrame sample(std::uint64_t sequence, std::uint64_t elapsed_ns, Origin origin,
                     double prediction_seconds, bool trackers_only);

  private:
    explicit OpenVrSession(vr::IVRSystem* system);

    vr::IVRSystem* system_ = nullptr;
    std::array<std::string, 64> serial_by_index_{};
};

} // namespace divive::probe
