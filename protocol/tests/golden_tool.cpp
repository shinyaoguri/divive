#include "golden_fixture.hpp"

#include "divive/protocol/envelope.hpp"
#include "divive/protocol/pose_codec.hpp"

#include <cstdlib>
#include <iomanip>
#include <iostream>

int main() {
    const auto result = divive::protocol::test::golden_packet();
    if (result.pose_error != divive::protocol::PoseCodecError::none) {
        std::cerr << "pose encode error: "
                  << divive::protocol::to_string(result.pose_error) << '\n';
        return EXIT_FAILURE;
    }
    if (result.packet_error != divive::protocol::PacketError::none) {
        std::cerr << "packet encode error: "
                  << divive::protocol::to_string(result.packet_error) << '\n';
        return EXIT_FAILURE;
    }

    std::cout << std::hex << std::setfill('0');
    for (const auto value : result.packet) {
        std::cout << std::setw(2) << std::to_integer<unsigned>(value);
    }
    std::cout << '\n';
    return EXIT_SUCCESS;
}
