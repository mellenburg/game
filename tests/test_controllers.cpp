#include <glm/glm.hpp>

#include "sim/ai_controller.h"
#include "sim/human_controller.h"
#include "sim/player.h"
#include "sim/satellite.h"
#include "sim/world.h"
#include "tests/test_util.h"

TEST(human_controller, launch_request_adds_satellite) {
    sim::World w;
    auto& h = w.AddPlayer("H", sim::PlayerKind::Human, glm::vec3(0.0f));
    sim::HumanController hc;
    hc.request_launch = true;
    hc.Tick(h, w, 0.016);
    EXPECT_EQ(h.satellite_count(), 1);
}

TEST(human_controller, destroy_request_removes_satellite) {
    sim::World w;
    auto& h = w.AddPlayer("H", sim::PlayerKind::Human, glm::vec3(0.0f));
    h.AddSatellite();
    sim::HumanController hc;
    hc.request_destroy = true;
    hc.Tick(h, w, 0.016);
    EXPECT_EQ(h.satellite_count(), 0);
}

TEST(human_controller, select_next_request_advances_selection) {
    sim::World w;
    auto& h = w.AddPlayer("H", sim::PlayerKind::Human, glm::vec3(0.0f));
    h.AddSatellite();
    h.AddSatellite();
    EXPECT_EQ(h.selected_index(), 1);
    sim::HumanController hc;
    hc.request_select_next = true;
    hc.Tick(h, w, 0.016);
    EXPECT_EQ(h.selected_index(), 0);
}

TEST(human_controller, dilation_step_adjusts_player_dilation) {
    sim::World w;
    auto& h = w.AddPlayer("H", sim::PlayerKind::Human, glm::vec3(0.0f));
    h.set_requested_dilation(100.0);
    sim::HumanController hc;
    hc.dilation_step = +5;
    hc.Tick(h, w, 0.016);
    EXPECT_NEAR(h.requested_dilation(), 105.0, 1e-9);
    hc.dilation_step = -50;
    hc.Tick(h, w, 0.016);
    EXPECT_NEAR(h.requested_dilation(), 55.0, 1e-9);
}

TEST(human_controller, maneuver_direction_passes_through_to_satellite) {
    sim::World w;
    auto& h = w.AddPlayer("H", sim::PlayerKind::Human, glm::vec3(0.0f));
    h.AddSatellite();
    sim::HumanController hc;
    hc.maneuver_direction = glm::vec3(1.0f, 0.0f, 0.0f);
    hc.Tick(h, w, 0.016);
    EXPECT_TRUE(glm::length(h.satellite(0).GetCurrentManeuver()) > 0.0f);
}

TEST(human_controller, consume_one_shots_clears_pulse_state) {
    sim::HumanController hc;
    hc.request_launch = true;
    hc.request_destroy = true;
    hc.request_select_next = true;
    hc.dilation_step = 7;
    hc.ConsumeOneShots();
    EXPECT_FALSE(hc.request_launch);
    EXPECT_FALSE(hc.request_destroy);
    EXPECT_FALSE(hc.request_select_next);
    EXPECT_EQ(hc.dilation_step, 0);
}

TEST(ai_controller, tick_does_not_crash_with_no_satellites) {
    sim::World w;
    auto& ai = w.AddPlayer("AI", sim::PlayerKind::Ai, glm::vec3(0.0f));
    sim::AiController c;
    c.Tick(ai, w, 0.016);
    EXPECT_EQ(ai.satellite_count(), 0);
}

TEST(ai_controller, tick_clears_selected_maneuver) {
    sim::World w;
    auto& ai = w.AddPlayer("AI", sim::PlayerKind::Ai, glm::vec3(0.0f));
    ai.AddSatellite();
    ai.satellite(0).SetManeuver(glm::vec3(1.0f, 1.0f, 1.0f));
    sim::AiController c;
    c.Tick(ai, w, 0.016);
    EXPECT_NEAR(glm::length(ai.satellite(0).GetCurrentManeuver()), 0.0, 1e-9);
}
