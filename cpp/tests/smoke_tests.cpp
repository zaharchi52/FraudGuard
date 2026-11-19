#include "fraudguard/csv_io.hpp"
#include "fraudguard/engine.hpp"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace fraudguard;
namespace fs = std::filesystem;

namespace {
void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

template <typename Action>
bool throwsOutOfRange(const Action& action) {
    try { action(); }
    catch (const std::out_of_range&) { return true; }
    catch (...) { return false; }
    return false;
}

Transaction makeTx(const std::string& id, long double amount,
                   const std::string& country = "DE",
                   const std::string& device = "D1",
                   const std::string& category = "groceries",
                   const std::string& currency = "EUR") {
    Transaction tx;
    tx.transaction_id = id;
    tx.client_id = "C1";
    tx.currency = currency;
    tx.amount = amount;
    tx.country = country;
    tx.device_id = device;
    tx.merchant_category = category;
    return tx;
}

std::vector<Transaction> readyHistory() {
    return {makeTx("H1", 20), makeTx("H2", 25), makeTx("H3", 30),
            makeTx("H4", 35), makeTx("H5", 40)};
}

std::vector<std::string> readLines(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    check(static_cast<bool>(input), "Cannot open output: " + path.string());
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(input, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        lines.push_back(line);
    }
    return lines;
}

// This deliberately small splitter is sufficient for the golden fixture, whose fields contain no commas.
std::vector<std::string> splitSimpleCsv(const std::string& line) {
    std::vector<std::string> result;
    std::stringstream stream(line);
    std::string field;
    while (std::getline(stream, field, ',')) result.push_back(field);
    if (!line.empty() && line.back() == ',') result.emplace_back();
    return result;
}

void testStatisticsAndBoundaries() {
    check(median({1, 3, 5}) == 3.0L, "odd median");
    check(median({1, 2, 3, 4}) == 2.5L, "even median");
    check(percentile95NearestRank({1, 2, 3, 4, 5}) == 5.0L, "p95 nearest rank n=5");
    check(percentile95NearestRank({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}) == 10.0L, "p95 nearest rank n=10");
    check(decisionForScore(0) == "APPROVE", "score 0");
    check(decisionForScore(29) == "APPROVE", "score 29");
    check(decisionForScore(30) == "REVIEW", "score 30");
    check(decisionForScore(59) == "REVIEW", "score 59");
    check(decisionForScore(60) == "BLOCK", "score 60");
    check(decisionForScore(100) == "BLOCK", "score 100");
    check(throwsOutOfRange([] { (void)decisionForScore(-1); }), "negative score must fail");
    check(throwsOutOfRange([] { (void)decisionForScore(101); }), "score above 100 must fail");
}

void testProfilesAndRules() {
    const auto history = readyHistory();
    const auto profile = buildProfile(history, "C1", "EUR");
    check(profile.status == ProfileStatus::Ready, "ready profile");
    check(profile.transaction_count == 5, "profile count");
    check(profile.median_amount == 30.0L, "profile median");
    check(profile.p95_amount == 40.0L, "profile p95");
    check(buildProfile({}, "C1", "EUR").status == ProfileStatus::ColdStart, "cold-start profile");

    auto limited_history = history;
    limited_history.pop_back();
    const auto limited = buildProfile(limited_history, "C1", "EUR");
    check(limited.status == ProfileStatus::LimitedHistory, "limited profile");
    check(evaluateRisk(makeTx("L1", 500, "FR", "NEW", "electronics"), limited, 1).empty(),
          "profile-only rules disabled for limited history");

    const auto unusual = evaluateRisk(makeTx("U1", 40.01L), profile, 1);
    check(unusual.size() == 1 && unusual[0].code == "UNUSUAL_AMOUNT" && unusual[0].points == 15,
          "unusual amount strictly above p95");
    const auto p95_boundary = evaluateRisk(makeTx("P95", 40.0L), profile, 1);
    check(p95_boundary.empty(), "amount equal to p95 is not unusual");
    const auto high_amount = evaluateRisk(makeTx("H1", 150.0L), profile, 1);
    check(high_amount.size() == 1 && high_amount[0].code == "HIGH_AMOUNT" && high_amount[0].points == 30,
          "high amount threshold is inclusive at 5x median");
    const auto new_attributes = evaluateRisk(makeTx("N1", 20, "FR", "D9", "electronics"), profile, 1);
    check(new_attributes.size() == 3, "new country/device/category factors");
    check(scoreForFactors(new_attributes) == 45, "attribute factors total 45");
    check(evaluateRisk(makeTx("V4", 20), profile, 4).empty(), "velocity not triggered at four");
    const auto velocity = evaluateRisk(makeTx("V5", 20), profile, 5);
    check(velocity.size() == 1 && velocity[0].code == "HIGH_VELOCITY", "velocity triggered at five");
    check(scoreForFactors({{"A", 80}, {"B", 40}}) == 100, "score capped at 100");

    const auto usd_profile = buildProfile(history, "C1", "USD");
    check(usd_profile.status == ProfileStatus::ColdStart, "profile is scoped by currency");
}

void testTimestamps() {
    std::int64_t utc = 0, offset = 0, next_ms = 0;
    check(parseIso8601("2026-10-28T10:00:00Z", utc), "UTC timestamp accepted");
    check(parseIso8601("2026-10-28T12:00:00+02:00", offset), "offset timestamp accepted");
    check(utc == offset, "equivalent offsets normalize to same instant");
    check(!parseIso8601("2026-10-28T10:00:00", offset), "timezone is required");
    check(!parseIso8601("2026-02-30T10:00:00Z", offset), "invalid calendar date rejected");
    check(!parseIso8601("2026-10-28T25:00:00Z", offset), "invalid hour rejected");
    check(parseIso8601("2026-10-28T10:00:00.125Z", utc), "milliseconds accepted");
    check(parseIso8601("2026-10-28T10:00:00.126Z", next_ms), "next millisecond accepted");
    check(next_ms - utc == 1, "millisecond precision preserved");
}


void testCsvValidation(const fs::path& temp_dir) {
    const auto csv_path = temp_dir / "quoted.csv";
    {
        std::ofstream out(csv_path, std::ios::binary);
        out << "\xEF\xBB\xBFtransaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id\r\n";
        out << "Q1,C1,2026-11-01T10:00:00Z,10.00,EUR,DE,\"food, dining\",D1\r\n";
        out << "Q1,C1,2026-11-01T10:01:00Z,11.00,EUR,DE,groceries,D1\r\n";
        out << "Q2,C1,2026-11-01T10:02:00Z,12.00,EUR,DE,groceries,D1\r\n";
    }
    std::vector<Transaction> transactions;
    std::vector<ProcessingError> errors;
    std::unordered_set<std::string> seen;
    check(loadTransactions(csv_path, transactions, seen, errors), "quoted CSV file loads");
    check(transactions.size() == 2, "valid rows load while duplicate IDs are rejected");
    check(transactions.front().merchant_category == "food, dining", "quoted comma is preserved");
    check(errors.size() == 1 && errors.front().error_code == "DUPLICATE_TRANSACTION_ID",
          "duplicate transaction id is reported");

    const auto malformed_path = temp_dir / "malformed.csv";
    {
        std::ofstream out(malformed_path, std::ios::binary);
        out << "transaction_id,client_id,timestamp,amount,currency,country,merchant_category,device_id\n";
        out << "Q3,C1,2026-11-01T10:00:00Z,10.00,EUR,DE,\"groceries\"suffix,D1\n";
    }
    transactions.clear(); errors.clear(); seen.clear();
    check(!loadTransactions(malformed_path, transactions, seen, errors), "malformed CSV file is rejected");
    check(errors.size() == 1 && errors.front().error_code == "CSV_PARSE_ERROR",
          "characters after closing quote are rejected consistently");
}

void testGoldenFixtures(const fs::path& root, const fs::path& temp_dir) {
    ProcessingOptions options;
    options.transactions_path = root / "data/conformance/transactions.csv";
    options.history_path = root / "data/conformance/history.csv";
    options.output_dir = temp_dir / "conformance";
    options.use_history = true;
    check(run(options) == 0, "conformance batch completed");

    const auto expected = readLines(root / "data/conformance/expected-results.csv");
    const auto actual = readLines(options.output_dir / "results.csv");
    check(actual.size() == expected.size(), "conformance result row count");
    for (std::size_t i = 1; i < expected.size(); ++i) {
        const auto e = splitSimpleCsv(expected[i]);
        const auto a = splitSimpleCsv(actual[i]);
        check(e.size() == 5 && a.size() >= 9, "conformance row column count");
        check(e[0] == a[0], "transaction order/id mismatch at row " + std::to_string(i));
        check(e[1] == a[5], "score mismatch for " + e[0]);
        check(e[2] == a[6], "decision mismatch for " + e[0]);
        check(e[3] == a[7], "risk factors mismatch for " + e[0]);
        check(e[4] == a[8], "profile status mismatch for " + e[0]);
    }

    ProcessingOptions invalid;
    invalid.transactions_path = root / "data/transactions_invalid.csv";
    invalid.history_path = root / "data/history.csv";
    invalid.output_dir = temp_dir / "invalid";
    check(run(invalid) == 0, "invalid-row batch continues and completes");
    const auto invalid_results = readLines(invalid.output_dir / "results.csv");
    const auto invalid_errors = readLines(invalid.output_dir / "errors.csv");
    check(invalid_results.size() == 2, "one valid invalid-fixture row is processed");
    check(invalid_results[1].rfind("T9004,", 0) == 0, "valid row after invalid rows is retained");
    check(invalid_errors.size() == 4, "three invalid rows are written to errors.csv");
}
}  // namespace

int main() {
    const fs::path root = fs::current_path();
    const fs::path temp_dir = fs::temp_directory_path() / "fraudguard-stage5-tests";
    try {
        fs::remove_all(temp_dir);
        fs::create_directories(temp_dir);
        testStatisticsAndBoundaries();
        testProfilesAndRules();
        testTimestamps();
        testCsvValidation(temp_dir);
        testGoldenFixtures(root, temp_dir);
        fs::remove_all(temp_dir);
        std::cout << "FraudGuard C++ tests passed: statistics, profiles, rules, timestamps, golden fixtures, CSV error recovery.\n";
        return 0;
    } catch (const std::exception& ex) {
        std::cerr << "FraudGuard C++ test failure: " << ex.what() << '\n';
        std::error_code ignored;
        fs::remove_all(temp_dir, ignored);
        return 1;
    }
}
