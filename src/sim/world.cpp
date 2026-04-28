#include <algorithm>
#include <limits>

#include "sim/world.h"

namespace sim {

World::World() = default;

Player& World::AddPlayer(std::string name, PlayerKind kind,
                         glm::vec3 team_color) {
    players_.push_back(std::make_unique<Player>(std::move(name), kind, team_color));
    return *players_.back();
}

int World::human_player_index() const {
    for (int i = 0; i < player_count(); ++i) {
        if (players_[i]->is_human()) return i;
    }
    return -1;
}

double World::EffectiveDilation() const {
    double best = std::numeric_limits<double>::infinity();
    bool any_human = false;
    for (const auto& p : players_) {
        if (!p->is_human()) continue;
        any_human = true;
        best = std::min(best, p->requested_dilation());
    }
    return any_human ? best : 1.0;
}

void World::Advance(double sim_dt_seconds) {
    if (sim_dt_seconds <= 0.0) return;
    for (auto& p : players_) {
        for (int i = 0; i < p->satellite_count(); ++i) {
            p->satellite(i).AdvanceTime(sim_dt_seconds);
        }
    }
}

void World::CloneStateFrom(const World& other) {
    players_.clear();
    players_.reserve(other.players_.size());
    for (const auto& src : other.players_) {
        auto p = std::make_unique<Player>(src->name(), src->kind(),
                                          src->team_color());
        p->CloneStateFrom(*src);
        players_.push_back(std::move(p));
    }
}

int World::total_satellite_count() const {
    int total = 0;
    for (const auto& p : players_) total += p->satellite_count();
    return total;
}

std::vector<World::SatRef> World::AllSatelliteRefs() const {
    std::vector<SatRef> refs;
    refs.reserve(total_satellite_count());
    for (int pi = 0; pi < player_count(); ++pi) {
        for (int si = 0; si < players_[pi]->satellite_count(); ++si) {
            refs.push_back({pi, si});
        }
    }
    return refs;
}

}  // namespace sim
