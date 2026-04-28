#ifndef GAME_TESTS_TEST_UTIL_H_
#define GAME_TESTS_TEST_UTIL_H_

// Minimal self-contained test framework. Avoids pulling in gtest / catch /
// doctest so CI only needs glm headers to compile the sim-layer suite.

#include <cmath>
#include <exception>
#include <functional>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

namespace test_util {

struct TestCase {
    std::string name;
    std::function<void()> fn;
};

inline std::vector<TestCase>& registry() {
    static std::vector<TestCase> tests;
    return tests;
}

struct Registrar {
    Registrar(const std::string& name, std::function<void()> fn) {
        registry().push_back({name, std::move(fn)});
    }
};

struct AssertionFailure : std::exception {
    std::string msg;
    explicit AssertionFailure(std::string m) : msg(std::move(m)) {}
    const char* what() const noexcept override { return msg.c_str(); }
};

inline int RunAll() {
    int failed = 0;
    for (const auto& t : registry()) {
        try {
            t.fn();
            std::cout << "[ OK ] " << t.name << "\n";
        } catch (const AssertionFailure& f) {
            std::cout << "[FAIL] " << t.name << ": " << f.what() << "\n";
            ++failed;
        } catch (const std::exception& e) {
            std::cout << "[FAIL] " << t.name << ": exception: " << e.what()
                      << "\n";
            ++failed;
        }
    }
    std::cout << "\n"
              << (registry().size() - failed) << "/" << registry().size()
              << " tests passed\n";
    return failed == 0 ? 0 : 1;
}

}  // namespace test_util

#define TEST(suite, name)                                                  \
    static void suite##_##name##_impl();                                   \
    static ::test_util::Registrar suite##_##name##_reg(                    \
        #suite "." #name, suite##_##name##_impl);                          \
    static void suite##_##name##_impl()

#define TEST_FAIL(msg)                                                     \
    do {                                                                   \
        std::ostringstream _oss;                                           \
        _oss << __FILE__ << ":" << __LINE__ << ": " << msg;                \
        throw ::test_util::AssertionFailure(_oss.str());                   \
    } while (0)

#define EXPECT_TRUE(cond)                                                  \
    do {                                                                   \
        if (!(cond)) TEST_FAIL("EXPECT_TRUE(" #cond ")");                  \
    } while (0)

#define EXPECT_FALSE(cond)                                                 \
    do {                                                                   \
        if ((cond)) TEST_FAIL("EXPECT_FALSE(" #cond ")");                  \
    } while (0)

#define EXPECT_EQ(a, b)                                                    \
    do {                                                                   \
        auto _va = (a);                                                    \
        auto _vb = (b);                                                    \
        if (!(_va == _vb)) {                                               \
            std::ostringstream _o;                                         \
            _o << "EXPECT_EQ(" #a ", " #b ") got " << _va << " vs " << _vb;\
            TEST_FAIL(_o.str());                                           \
        }                                                                  \
    } while (0)

#define EXPECT_NEAR(a, b, eps)                                             \
    do {                                                                   \
        double _va = (a);                                                  \
        double _vb = (b);                                                  \
        double _e = (eps);                                                 \
        if (std::fabs(_va - _vb) > _e) {                                   \
            std::ostringstream _o;                                         \
            _o << "EXPECT_NEAR(" #a ", " #b ", " #eps ") |" << _va << "-"  \
               << _vb << "|=" << std::fabs(_va - _vb) << " > " << _e;      \
            TEST_FAIL(_o.str());                                           \
        }                                                                  \
    } while (0)

#endif  // GAME_TESTS_TEST_UTIL_H_
