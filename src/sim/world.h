#ifndef GAME_SIM_WORLD_H_
#define GAME_SIM_WORLD_H_

#include <memory>
#include <vector>

#include "sim/player.h"

namespace sim {

// Top-level simulation state. Owns players (and their satellites). Knows
// nothing about windowing, input, or rendering.
class World {
  public:
    World();

    // Roster management. Returned references stay valid for the player's
    // lifetime; satellite vectors use unique_ptr internally to keep
    // satellite addresses stable across resizes.
    Player& AddPlayer(std::string name, PlayerKind kind, glm::vec3 team_color);

    int player_count() const { return static_cast<int>(players_.size()); }
    Player& player(int i) { return *players_[i]; }
    const Player& player(int i) const { return *players_[i]; }

    // Index of the (single) human player, or -1 if there are no humans.
    int human_player_index() const;

    // Effective simulation seconds per real second. Min over human players'
    // requested_dilation; defaults to 1.0 if there are no humans.
    double EffectiveDilation() const;

    // Advance every satellite by the same simulated dt.
    void Advance(double sim_dt_seconds);

    // Deep-copy player+satellite state from `other`. Used to seed the
    // planning-mode shadow each tick.
    void CloneStateFrom(const World& other);

    // Total satellites across all players.
    int total_satellite_count() const;

    // Linearised view over all satellites (used by HUD / view layer).
    struct SatRef {
        int player_index;
        int satellite_index;
    };
    std::vector<SatRef> AllSatelliteRefs() const;

  private:
    std::vector<std::unique_ptr<Player>> players_;
};

}  // namespace sim

#endif  // GAME_SIM_WORLD_H_
