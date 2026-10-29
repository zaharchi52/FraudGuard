#include "fraudguard/engine.hpp"

#include <cassert>
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace fraudguard;

int main() {
    assert(static_cast<double>(median({1, 3, 5})) == 3.0);
    assert(static_cast<double>(median({1, 2, 3, 4})) == 2.5);
    assert(static_cast<double>(percentile95NearestRank({1, 2, 3, 4, 5})) == 5.0);
    assert(decisionForScore(29) == "APPROVE");
    assert(decisionForScore(30) == "REVIEW");
    assert(decisionForScore(59) == "REVIEW");
    assert(decisionForScore(60) == "BLOCK");
    std::int64_t utc = 0, offset = 0;
    assert(parseIso8601("2026-10-28T10:00:00Z", utc));
    assert(parseIso8601("2026-10-28T12:00:00+02:00", offset));
    assert(utc == offset);
    assert(!parseIso8601("2026-10-28T10:00:00", offset));
    std::int64_t first_ms = 0, next_ms = 0;
    assert(parseIso8601("2026-10-28T10:00:00.125Z", first_ms));
    assert(parseIso8601("2026-10-28T10:00:00.126Z", next_ms));
    assert(next_ms - first_ms == 1);
    std::cout << "Smoke tests passed\n";
    return 0;
}
