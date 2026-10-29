#include "fraudguard/engine.hpp"

#include <gtest/gtest.h>

#include <stdexcept>
#include <vector>

using namespace fraudguard;

namespace {
Transaction makeTx(const std::string& id, long double amount,
                   const std::string& country = "DE",
                   const std::string& device = "D1",
                   const std::string& category = "groceries") {
    Transaction tx;
    tx.transaction_id = id;
    tx.client_id = "C1";
    tx.currency = "EUR";
    tx.amount = amount;
    tx.country = country;
    tx.device_id = device;
    tx.merchant_category = category;
    return tx;
}

std::vector<Transaction> readyHistory() {
    return {
        makeTx("H1", 20), makeTx("H2", 25), makeTx("H3", 30),
        makeTx("H4", 35), makeTx("H5", 40)};
}
}  // namespace

TEST(StatisticsTest, MedianSupportsOddAndEvenCollections) {
    EXPECT_DOUBLE_EQ(static_cast<double>(median({5, 1, 3})), 3.0);
    EXPECT_DOUBLE_EQ(static_cast<double>(median({4, 1, 3, 2})), 2.5);
}

TEST(StatisticsTest, P95UsesNearestRank) {
    EXPECT_DOUBLE_EQ(static_cast<double>(percentile95NearestRank({1, 2, 3, 4, 5})), 5.0);
    EXPECT_DOUBLE_EQ(static_cast<double>(percentile95NearestRank({1, 2, 3, 4, 5, 6, 7, 8, 9, 10})), 10.0);
}

TEST(StatisticsTest, EmptyCollectionThrows) {
    EXPECT_THROW(median({}), std::invalid_argument);
    EXPECT_THROW(percentile95NearestRank({}), std::invalid_argument);
}

TEST(ValidationTest, ParsesUtcAndOffsetTimestamps) {
    std::int64_t utc = 0, offset = 0;
    ASSERT_TRUE(parseIso8601("2026-10-28T10:00:00Z", utc));
    ASSERT_TRUE(parseIso8601("2026-10-28T12:00:00+02:00", offset));
    EXPECT_EQ(utc, offset);
}

TEST(ValidationTest, RejectsTimestampWithoutTimezoneAndBadCalendarDate) {
    std::int64_t milliseconds = 0;
    EXPECT_FALSE(parseIso8601("2026-10-28T10:00:00", milliseconds));
    EXPECT_FALSE(parseIso8601("2026-02-30T10:00:00Z", milliseconds));
}

TEST(ValidationTest, PreservesMillisecondTimestampPrecision) {
    std::int64_t first = 0, next = 0, offset = 0;
    ASSERT_TRUE(parseIso8601("2026-10-28T10:00:00.125Z", first));
    ASSERT_TRUE(parseIso8601("2026-10-28T10:00:00.126Z", next));
    ASSERT_TRUE(parseIso8601("2026-10-28T12:00:00.125+02:00", offset));
    EXPECT_EQ(next - first, 1);
    EXPECT_EQ(first, offset);
}

TEST(DecisionTest, CoversAllDecisionBoundaries) {
    EXPECT_EQ(decisionForScore(0), "APPROVE");
    EXPECT_EQ(decisionForScore(29), "APPROVE");
    EXPECT_EQ(decisionForScore(30), "REVIEW");
    EXPECT_EQ(decisionForScore(59), "REVIEW");
    EXPECT_EQ(decisionForScore(60), "BLOCK");
    EXPECT_EQ(decisionForScore(100), "BLOCK");
    EXPECT_THROW(decisionForScore(101), std::out_of_range);
}

TEST(ProfileTest, DistinguishesColdStartLimitedAndReady) {
    EXPECT_EQ(buildProfile({}, "C1", "EUR").status, ProfileStatus::ColdStart);
    auto history = readyHistory();
    history.pop_back();
    EXPECT_EQ(buildProfile(history, "C1", "EUR").status, ProfileStatus::LimitedHistory);
    history = readyHistory();
    const auto profile = buildProfile(history, "C1", "EUR");
    EXPECT_EQ(profile.status, ProfileStatus::Ready);
    EXPECT_EQ(profile.transaction_count, 5);
    EXPECT_DOUBLE_EQ(static_cast<double>(profile.median_amount), 30.0);
    EXPECT_DOUBLE_EQ(static_cast<double>(profile.p95_amount), 40.0);
}

TEST(RulesTest, HighAmountAndUnusualAmountAreMutuallyExclusive) {
    const auto profile = buildProfile(readyHistory(), "C1", "EUR");
    const auto unusual = evaluateRisk(makeTx("T1", 41), profile, 1);
    ASSERT_EQ(unusual.size(), 1u);
    EXPECT_EQ(unusual[0].code, "UNUSUAL_AMOUNT");
    EXPECT_EQ(unusual[0].points, 15);
    const auto high = evaluateRisk(makeTx("T2", 150), profile, 1);
    ASSERT_EQ(high.size(), 1u);
    EXPECT_EQ(high[0].code, "HIGH_AMOUNT");
    EXPECT_EQ(high[0].points, 30);
}

TEST(RulesTest, HighVelocityStartsAtFifthAttempt) {
    const auto profile = buildProfile(readyHistory(), "C1", "EUR");
    EXPECT_TRUE(evaluateRisk(makeTx("T1", 30), profile, 4).empty());
    const auto factors = evaluateRisk(makeTx("T2", 30), profile, 5);
    ASSERT_EQ(factors.size(), 1u);
    EXPECT_EQ(factors[0].code, "HIGH_VELOCITY");
}

TEST(RulesTest, DetectsNewCountryDeviceAndCategory) {
    const auto profile = buildProfile(readyHistory(), "C1", "EUR");
    const auto factors = evaluateRisk(makeTx("T1", 30, "FR", "D9", "electronics"), profile, 1);
    ASSERT_EQ(factors.size(), 3u);
    EXPECT_EQ(factors[0].code, "NEW_COUNTRY");
    EXPECT_EQ(factors[1].code, "NEW_DEVICE");
    EXPECT_EQ(factors[2].code, "NEW_CATEGORY");
    EXPECT_EQ(scoreForFactors(factors), 45);
}

TEST(RulesTest, ProfileRulesAreDisabledForLimitedHistory) {
    auto history = readyHistory();
    history.pop_back();
    const auto profile = buildProfile(history, "C1", "EUR");
    const auto factors = evaluateRisk(makeTx("T1", 500, "FR", "D9", "electronics"), profile, 1);
    EXPECT_TRUE(factors.empty());
}

TEST(ScoringTest, ScoreIsCappedAtOneHundred) {
    EXPECT_EQ(scoreForFactors({{"A", 80}, {"B", 40}}), 100);
}
