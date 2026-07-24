#pragma once

#include "divive/probe/model.hpp"
#include "divive/probe/options.hpp"

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace divive::probe {

std::string json_escape(std::string_view value);

std::string serialize_probe_start(std::string_view wall_time_utc,
                                  std::string_view sdk_version,
                                  std::string_view runtime_path,
                                  const Options& options,
                                  const SchedulerInfo& scheduler);

std::string serialize_inventory(std::uint64_t elapsed_ns,
                                const std::vector<DeviceInventory>& devices);

std::string serialize_pose_frame(const PoseFrame& frame);
std::string serialize_summary(const ProbeSummary& summary);

std::string serialize_error(std::string_view code, std::string_view message,
                            std::uint64_t elapsed_ns = 0);

} // namespace divive::probe
