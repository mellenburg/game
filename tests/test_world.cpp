#include <glm/glm.hpp>

#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"
#include "tests/test_util.h"

namespace {

sim::Player& AddHuman(sim::World& w, const char* name = "H") {
    return w.AddPlayer(name, sim::PlayerKind::Human, glm::vec3(0.0f));
}

sim::Player& AddAi(sim::World& w, const char* name = "A") {
    return w.AddPlayer(name, sim::PlayerKind::Ai, glm::vec3(0.0f));
}

}  // namespace

TEST(world, effective_dilation_with_one_human) {
    sim::World w;
    AddHuman(w).set_requested_dilation(50.0);
    EXPECT_NEAR(w.EffectiveDilation(), 50.0, 1e-9);
}

TEST(world, effective_dilation_takes_min_over_humans) {
    sim::World w;
    AddHuman(w, "A").set_requested_dilation(100.0);
    AddHuman(w, "B").set_requested_dilation(20.0);
    EXPECT_NEAR(w.EffectiveDilation(), 20.0, 1e-9);
}

TEST(world, effective_dilation_ignores_ai_players) {
    sim::World w;
    AddHuman(w).set_requested_dilation(7.0);
    AddAi(w).set_requested_dilation(2.0);
    EXPECT_NEAR(w.EffectiveDilation(), 7.0, 1e-9);
}

TEST(world, effective_dilation_no_humans_returns_one) {
    sim::World w;
    AddAi(w);
    EXPECT_NEAR(w.EffectiveDilation(), 1.0, 1e-9);
}

TEST(world, human_player_index_finds_first_human) {
    sim::World w;
    AddAi(w, "A0");
    AddHuman(w, "H");
    AddAi(w, "A1");
    EXPECT_EQ(w.human_player_index(), 1);
}

TEST(world, human_player_index_minus_one_when_no_humans) {
    sim::World w;
    AddAi(w);
    EXPECT_EQ(w.human_player_index(), -1);
}

TEST(world, advance_propagates_all_satellites) {
    sim::World w;
    auto& a = AddHuman(w, "A");
    auto& b = AddAi(w, "B");
    a.AddSatellite();
    b.AddSatellite();
    glm::vec3 r_a0 = a.satellite(0).GetR();
    glm::vec3 r_b0 = b.satellite(0).GetR();
    w.Advance(60.0);
    EXPECT_TRUE(glm::distance(a.satellite(0).GetR(), r_a0) > 0.0f);
    EXPECT_TRUE(glm::distance(b.satellite(0).GetR(), r_b0) > 0.0f);
}

TEST(world, advance_zero_is_noop) {
    sim::World w;
    auto& h = AddHuman(w);
    h.AddSatellite();
    glm::vec3 r0 = h.satellite(0).GetR();
    w.Advance(0.0);
    EXPECT_NEAR(glm::distance(h.satellite(0).GetR(), r0), 0.0, 1e-9);
}

TEST(world, total_satellite_count_aggregates) {
    sim::World w;
    auto& a = AddHuman(w, "A");
    auto& b = AddAi(w, "B");
    EXPECT_EQ(w.total_satellite_count(), 0);
    a.AddSatellite();
    a.AddSatellite();
    b.AddSatellite();
    EXPECT_EQ(w.total_satellite_count(), 3);
}

TEST(world, clone_state_is_deep_copy) {
    sim::World live;
    auto& h = AddHuman(live);
    h.AddSatellite();

    sim::World shadow;
    shadow.CloneStateFrom(live);
    EXPECT_EQ(shadow.player_count(), 1);
    EXPECT_EQ(shadow.player(0).satellite_count(), 1);

    // Mutating live must not touch shadow.
    live.Advance(1000.0);
    glm::vec3 live_r = live.player(0).satellite(0).GetR();
    glm::vec3 shadow_r = shadow.player(0).satellite(0).GetR();
    EXPECT_TRUE(glm::distance(live_r, shadow_r) > 1e-3f);
}

TEST(world, all_satellite_refs_walks_every_satellite) {
    sim::World w;
    auto& a = AddHuman(w, "A");
    auto& b = AddAi(w, "B");
    a.AddSatellite();
    b.AddSatellite();
    b.AddSatellite();
    auto refs = w.AllSatelliteRefs();
    EXPECT_EQ(static_cast<int>(refs.size()), 3);
    EXPECT_EQ(refs[0].player_index, 0);
    EXPECT_EQ(refs[0].satellite_index, 0);
    EXPECT_EQ(refs[1].player_index, 1);
    EXPECT_EQ(refs[1].satellite_index, 0);
    EXPECT_EQ(refs[2].player_index, 1);
    EXPECT_EQ(refs[2].satellite_index, 1);
}
