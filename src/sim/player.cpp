#include <algorithm>

#include "sim/player.h"

namespace sim {

Player::Player(std::string name, PlayerKind kind, glm::vec3 team_color)
    : name_(std::move(name)), kind_(kind), team_color_(team_color) {}

Satellite* Player::AddSatellite(const SatelliteSpec& spec) {
    satellites_.push_back(std::make_unique<Satellite>(spec));
    selected_index_ = static_cast<int>(satellites_.size()) - 1;
    return satellites_.back().get();
}

bool Player::RemoveSelected() {
    if (selected_index_ < 0 ||
        selected_index_ >= static_cast<int>(satellites_.size())) {
        return false;
    }
    satellites_.erase(satellites_.begin() + selected_index_);
    if (satellites_.empty()) {
        selected_index_ = -1;
    } else if (selected_index_ >= static_cast<int>(satellites_.size())) {
        selected_index_ = static_cast<int>(satellites_.size()) - 1;
    }
    return true;
}

void Player::SelectNext() {
    if (satellites_.empty()) {
        selected_index_ = -1;
        return;
    }
    selected_index_ =
        (selected_index_ + 1) % static_cast<int>(satellites_.size());
}

Satellite* Player::selected() {
    if (selected_index_ < 0) return nullptr;
    return satellites_[selected_index_].get();
}

const Satellite* Player::selected() const {
    if (selected_index_ < 0) return nullptr;
    return satellites_[selected_index_].get();
}

void Player::set_requested_dilation(double v) {
    requested_dilation_ = std::max(1.0, v);
}

void Player::CloneStateFrom(const Player& other) {
    selected_index_ = other.selected_index_;
    requested_dilation_ = other.requested_dilation_;
    satellites_.clear();
    satellites_.reserve(other.satellites_.size());
    for (const auto& sat : other.satellites_) {
        auto copy = std::make_unique<Satellite>(sat->spec());
        copy->CloneStateFrom(*sat);
        satellites_.push_back(std::move(copy));
    }
}

}  // namespace sim
