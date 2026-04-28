#include <glm/glm.hpp>

#include "sim/player.h"
#include "sim/satellite.h"
#include "tests/test_util.h"

namespace {
sim::Player MakePlayer() {
    return sim::Player("P", sim::PlayerKind::Human, glm::vec3(1.0f));
}
}  // namespace

TEST(player, starts_empty_with_no_selection) {
    auto p = MakePlayer();
    EXPECT_EQ(p.satellite_count(), 0);
    EXPECT_EQ(p.selected_index(), -1);
    EXPECT_TRUE(p.selected() == nullptr);
}

TEST(player, add_satellite_selects_new_entry) {
    auto p = MakePlayer();
    p.AddSatellite();
    EXPECT_EQ(p.satellite_count(), 1);
    EXPECT_EQ(p.selected_index(), 0);
    p.AddSatellite();
    EXPECT_EQ(p.satellite_count(), 2);
    EXPECT_EQ(p.selected_index(), 1);
}

TEST(player, select_next_wraps_around) {
    auto p = MakePlayer();
    p.AddSatellite();
    p.AddSatellite();
    p.AddSatellite();
    EXPECT_EQ(p.selected_index(), 2);
    p.SelectNext();
    EXPECT_EQ(p.selected_index(), 0);
    p.SelectNext();
    EXPECT_EQ(p.selected_index(), 1);
}

TEST(player, remove_keeps_selection_in_bounds) {
    auto p = MakePlayer();
    p.AddSatellite();
    p.AddSatellite();
    EXPECT_EQ(p.selected_index(), 1);
    EXPECT_TRUE(p.RemoveSelected());
    EXPECT_EQ(p.satellite_count(), 1);
    EXPECT_EQ(p.selected_index(), 0);
    EXPECT_TRUE(p.RemoveSelected());
    EXPECT_EQ(p.satellite_count(), 0);
    EXPECT_EQ(p.selected_index(), -1);
}

TEST(player, remove_with_nothing_selected_is_noop) {
    auto p = MakePlayer();
    EXPECT_FALSE(p.RemoveSelected());
}

TEST(player, requested_dilation_floors_at_one) {
    auto p = MakePlayer();
    p.set_requested_dilation(0.0);
    EXPECT_NEAR(p.requested_dilation(), 1.0, 1e-9);
    p.set_requested_dilation(-5.0);
    EXPECT_NEAR(p.requested_dilation(), 1.0, 1e-9);
    p.set_requested_dilation(42.5);
    EXPECT_NEAR(p.requested_dilation(), 42.5, 1e-9);
}

TEST(player, kind_flags_are_consistent) {
    auto h = sim::Player("H", sim::PlayerKind::Human, glm::vec3(0));
    auto a = sim::Player("A", sim::PlayerKind::Ai, glm::vec3(0));
    EXPECT_TRUE(h.is_human());
    EXPECT_FALSE(a.is_human());
}

TEST(player, satellites_have_stable_addresses_across_adds) {
    auto p = MakePlayer();
    p.AddSatellite();
    sim::Satellite* first = &p.satellite(0);
    for (int i = 0; i < 32; ++i) p.AddSatellite();
    EXPECT_TRUE(&p.satellite(0) == first);
}
