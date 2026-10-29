#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

namespace fraudguard {

inline constexpr int MIN_HISTORY_SIZE = 5;
inline constexpr std::int64_t VELOCITY_WINDOW_MILLISECONDS = 10 * 60 * 1000;

struct Transaction {
    std::string transaction_id;
    std::string client_id;
    std::string timestamp_text;
    std::string amount_text;
    std::string currency;
    std::string country;
    std::string merchant_category;
    std::string device_id;
    long double amount = 0.0L;
    std::int64_t timestamp_epoch_milliseconds = 0;
    std::size_t line_number = 0;
};

enum class ProfileStatus { ColdStart, LimitedHistory, Ready };

struct ClientProfile {
    std::string client_id;
    std::string currency;
    int transaction_count = 0;
    ProfileStatus status = ProfileStatus::ColdStart;
    long double median_amount = 0.0L;
    long double p95_amount = 0.0L;
    std::vector<std::string> countries;
    std::vector<std::string> devices;
    std::vector<std::string> categories;
};

struct RiskFactor {
    std::string code;
    int points = 0;
};

struct ScoredTransaction {
    Transaction transaction;
    int risk_score = 0;
    std::string decision;
    ProfileStatus profile_status = ProfileStatus::ColdStart;
    std::vector<RiskFactor> factors;
};

struct ProcessingOptions {
    std::filesystem::path transactions_path = "data/transactions.csv";
    std::filesystem::path history_path = "data/history.csv";
    std::filesystem::path output_dir = "reports";
    bool use_history = true;
};

long double median(std::vector<long double> values);
long double percentile95NearestRank(std::vector<long double> values);
bool parseIso8601(const std::string& text, std::int64_t& epoch_milliseconds);
std::string toString(ProfileStatus status);
std::string decisionForScore(int score);
ClientProfile buildProfile(const std::vector<Transaction>& history,
                           const std::string& client_id,
                           const std::string& currency);
std::vector<RiskFactor> evaluateRisk(const Transaction& transaction,
                                     const ClientProfile& profile,
                                     int velocity_count);
int scoreForFactors(const std::vector<RiskFactor>& factors);
int run(const ProcessingOptions& options);

}  // namespace fraudguard
