#ifndef GAME_SIM_PLAYER_H_
#define GAME_SIM_PLAYER_H_

#include <memory>
#include <string>
#include <vector>

#define GLM_FORCE_RADIANS
#include <glm/glm.hpp>

#include "sim/satellite.h"
#include "sim/satellite_spec.h"

namespace sim {

enum class PlayerKind { Human, Ai };

// A player is the unit of authority: owns satellites, exposes a focus, and
// (if human) contributes a vote to the world's time dilation.
class Player {
  public:
    Player(std::string name, PlayerKind kind, glm::vec3 team_color);

    const std::string& name() const { return name_; }
    PlayerKind kind() const { return kind_; }
    bool is_human() const { return kind_ == PlayerKind::Human; }

    glm::vec3 team_color() const { return team_color_; }
    glm::vec3 selected_color() const { return selected_color_; }

    Satellite* AddSatellite(const SatelliteSpec& spec = {});
    bool RemoveSelected();
    void SelectNext();
    Satellite* selected();
    const Satellite* selected() const;
    int selected_index() const { return selected_index_; }

    int satellite_count() const { return static_cast<int>(satellites_.size()); }
    Satellite& satellite(int i) { return *satellites_[i]; }
    const Satellite& satellite(int i) const { return *satellites_[i]; }

    // Human-only: the dilation factor this player would prefer. The world
    // collapses these into a single effective rate (min across humans).
    double requested_dilation() const { return requested_dilation_; }
    void set_requested_dilation(double v);

    // Deep-copy state from `other` (specs + orbits + selection). Used by the
    // planning-mode shadow. Both players must be the same identity.
    void CloneStateFrom(const Player& other);

  private:
    std::string name_;
    PlayerKind kind_;
    glm::vec3 team_color_;
    glm::vec3 selected_color_{0.0f, 1.0f, 0.0f};
    std::vector<std::unique_ptr<Satellite>> satellites_;
    int selected_index_ = -1;
    // Simulated seconds per real second. Old harness ran at 30 FPS with an
    // integer time_factor of 500 (so 500/30 sim s per frame); per real
    // second that's 500x real-time speed.
    double requested_dilation_ = 500.0;
};

}  // namespace sim

#endif  // GAME_SIM_PLAYER_H_
