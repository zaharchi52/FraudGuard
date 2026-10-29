#include "fraudguard/engine.hpp"
#include "fraudguard/csv_io.hpp"

#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace fraudguard {
namespace {
bool contains(const std::vector<std::string>& values, const std::string& value) {
    return std::find(values.begin(), values.end(), value) != values.end();
}

void addUnique(std::vector<std::string>& values, const std::string& value) {
    if (!contains(values, value)) values.push_back(value);
}
}  // namespace

long double median(std::vector<long double> values) {
    if (values.empty()) throw std::invalid_argument("median() requires at least one value");
    std::sort(values.begin(), values.end());
    const std::size_t mid = values.size() / 2;
    if (values.size() % 2 == 1) return values[mid];
    return (values[mid - 1] + values[mid]) / 2.0L;
}

long double percentile95NearestRank(std::vector<long double> values) {
    if (values.empty()) throw std::invalid_argument("percentile95NearestRank() requires at least one value");
    std::sort(values.begin(), values.end());
    const auto rank = static_cast<std::size_t>(std::ceil(0.95L * static_cast<long double>(values.size())));
    return values[std::max<std::size_t>(1, rank) - 1];
}

bool parseIso8601(const std::string& text, std::int64_t& epoch_milliseconds) {
    // Accepted form: YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM).
    if (text.size() < 20 || text[4] != '-' || text[7] != '-' || text[10] != 'T' ||
        text[13] != ':' || text[16] != ':') return false;
    auto number = [&](std::size_t pos, std::size_t len, int& value) -> bool {
        if (pos + len > text.size()) return false;
        value = 0;
        for (std::size_t i = pos; i < pos + len; ++i) {
            if (text[i] < '0' || text[i] > '9') return false;
            value = value * 10 + (text[i] - '0');
        }
        return true;
    };
    int year, month, day, hour, minute, second;
    if (!number(0, 4, year) || !number(5, 2, month) || !number(8, 2, day) ||
        !number(11, 2, hour) || !number(14, 2, minute) || !number(17, 2, second)) return false;
    if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return false;
    static const int month_days[] = {31,28,31,30,31,30,31,31,30,31,30,31};
    const bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    const int max_day = month_days[month - 1] + ((month == 2 && leap) ? 1 : 0);
    if (day < 1 || day > max_day) return false;

    std::size_t pos = 19;
    int fractional_milliseconds = 0;
    if (pos < text.size() && text[pos] == '.') {
        ++pos;
        const std::size_t start = pos;
        int digits_used = 0;
        while (pos < text.size() && text[pos] >= '0' && text[pos] <= '9') {
            if (digits_used < 3) {
                fractional_milliseconds = fractional_milliseconds * 10 + (text[pos] - '0');
                ++digits_used;
            }
            ++pos;
        }
        if (pos == start) return false;
        while (digits_used < 3) {
            fractional_milliseconds *= 10;
            ++digits_used;
        }
    }
    int offset_seconds = 0;
    if (pos < text.size() && text[pos] == 'Z') {
        ++pos;
    } else if (pos + 6 == text.size() && (text[pos] == '+' || text[pos] == '-') && text[pos + 3] == ':') {
        int offset_hour, offset_minute;
        if (!number(pos + 1, 2, offset_hour) || !number(pos + 4, 2, offset_minute) ||
            offset_hour > 23 || offset_minute > 59) return false;
        offset_seconds = (offset_hour * 60 + offset_minute) * 60;
        if (text[pos] == '-') offset_seconds = -offset_seconds;
        pos += 6;
    } else {
        return false;
    }
    if (pos != text.size()) return false;

    // Howard Hinnant's civil-date conversion, independent of platform time APIs.
    int y = year;
    const unsigned m = static_cast<unsigned>(month);
    const unsigned d = static_cast<unsigned>(day);
    y -= (m <= 2);
    const int era = (y >= 0 ? y : y - 399) / 400;
    const unsigned yoe = static_cast<unsigned>(y - era * 400);
    const unsigned adjusted_month = m > 2 ? m - 3 : m + 9;
    const unsigned doy = (153 * adjusted_month + 2) / 5 + d - 1;
    const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    const std::int64_t days = static_cast<std::int64_t>(era) * 146097 + static_cast<std::int64_t>(doe) - 719468;
    const std::int64_t utc_seconds = days * 86400 + hour * 3600 + minute * 60 + second - offset_seconds;
    epoch_milliseconds = utc_seconds * 1000 + fractional_milliseconds;
    return true;
}

std::string toString(ProfileStatus status) {
    switch (status) {
        case ProfileStatus::ColdStart: return "COLD_START";
        case ProfileStatus::LimitedHistory: return "LIMITED_HISTORY";
        case ProfileStatus::Ready: return "READY";
    }
    return "COLD_START";
}

std::string decisionForScore(int score) {
    if (score < 0 || score > 100) throw std::out_of_range("score must be in range 0..100");
    if (score < 30) return "APPROVE";
    if (score < 60) return "REVIEW";
    return "BLOCK";
}

ClientProfile buildProfile(const std::vector<Transaction>& history,
                           const std::string& client_id,
                           const std::string& currency) {
    ClientProfile profile;
    profile.client_id = client_id;
    profile.currency = currency;
    std::vector<long double> amounts;
    for (const auto& tx : history) {
        if (tx.client_id != client_id || tx.currency != currency) continue;
        ++profile.transaction_count;
        amounts.push_back(tx.amount);
        addUnique(profile.countries, tx.country);
        addUnique(profile.devices, tx.device_id);
        addUnique(profile.categories, tx.merchant_category);
    }
    if (profile.transaction_count == 0) {
        profile.status = ProfileStatus::ColdStart;
    } else if (profile.transaction_count < MIN_HISTORY_SIZE) {
        profile.status = ProfileStatus::LimitedHistory;
    } else {
        profile.status = ProfileStatus::Ready;
        profile.median_amount = median(amounts);
        profile.p95_amount = percentile95NearestRank(amounts);
    }
    return profile;
}

std::vector<RiskFactor> evaluateRisk(const Transaction& tx,
                                     const ClientProfile& profile,
                                     int velocity_count) {
    std::vector<RiskFactor> factors;
    if (profile.status == ProfileStatus::Ready) {
        if (tx.amount >= 5.0L * profile.median_amount) {
            factors.push_back({"HIGH_AMOUNT", 30});
        } else if (tx.amount > profile.p95_amount) {
            factors.push_back({"UNUSUAL_AMOUNT", 15});
        }
    }
    if (velocity_count >= 5) factors.push_back({"HIGH_VELOCITY", 25});
    if (profile.status == ProfileStatus::Ready) {
        if (!contains(profile.countries, tx.country)) factors.push_back({"NEW_COUNTRY", 20});
        if (!contains(profile.devices, tx.device_id)) factors.push_back({"NEW_DEVICE", 15});
        if (!contains(profile.categories, tx.merchant_category)) factors.push_back({"NEW_CATEGORY", 10});
    }
    return factors;
}

int scoreForFactors(const std::vector<RiskFactor>& factors) {
    int score = 0;
    for (const auto& factor : factors) score += factor.points;
    return std::min(100, score);
}

int run(const ProcessingOptions& options) {
    std::vector<ProcessingError> errors;
    std::vector<Transaction> history;
    std::vector<Transaction> input_transactions;
    std::unordered_set<std::string> seen_ids;
    bool fatal_input_error = false;

    if (options.use_history) {
        if (std::filesystem::exists(options.history_path)) {
            const bool loaded = loadTransactions(options.history_path, history, seen_ids, errors);
            if (!loaded) {
                std::cerr << "Предупреждение: историю не удалось прочитать; расчёт продолжится без неё.\n";
                history.clear();
                seen_ids.clear();
            }
        } else {
            std::cerr << "Предупреждение: файл истории не найден (" << options.history_path
                      << "); клиенты будут обрабатываться без профиля.\n";
        }
    }

    const bool input_loaded = loadTransactions(options.transactions_path, input_transactions,
                                               seen_ids, errors);
    if (!input_loaded) {
        fatal_input_error = true;
        std::cerr << "Ошибка: входной файл транзакций не загружен.\n";
    }

    // Build velocity windows from all valid new transactions. This makes results independent
    // of the input row order, while the final report retains that original order.
    std::unordered_map<std::string, std::vector<std::int64_t>> client_times;
    for (const auto& tx : input_transactions) client_times[tx.client_id].push_back(tx.timestamp_epoch_milliseconds);
    for (auto& [client, times] : client_times) {
        (void)client;
        std::sort(times.begin(), times.end());
    }

    std::vector<ScoredTransaction> results;
    results.reserve(input_transactions.size());
    for (const auto& tx : input_transactions) {
        const ClientProfile profile = buildProfile(history, tx.client_id, tx.currency);
        const auto& times = client_times[tx.client_id];
        const auto lower = std::lower_bound(times.begin(), times.end(), tx.timestamp_epoch_milliseconds - VELOCITY_WINDOW_MILLISECONDS);
        const auto upper = std::upper_bound(times.begin(), times.end(), tx.timestamp_epoch_milliseconds);
        const int velocity_count = static_cast<int>(std::distance(lower, upper));
        auto factors = evaluateRisk(tx, profile, velocity_count);
        const int score = scoreForFactors(factors);
        results.push_back({tx, score, decisionForScore(score), profile.status, std::move(factors)});
    }

    if (!writeReports(options.output_dir, results, errors)) return 2;
    std::size_t alert_count = 0;
    for (const auto& result : results) {
        if (result.decision == "REVIEW" || result.decision == "BLOCK") ++alert_count;
    }
    std::cout << "FraudGuard: обработка завершена\n"
              << "  Валидных исторических операций: " << history.size() << '\n'
              << "  Скорированных транзакций: " << results.size() << '\n'
              << "  Алертов (REVIEW/BLOCK): " << alert_count << '\n'
              << "  Ошибок строк/файлов: " << errors.size() << '\n'
              << "  Отчёты: " << options.output_dir.string() << '\n';
    return fatal_input_error ? 1 : 0;
}

}  // namespace fraudguard
