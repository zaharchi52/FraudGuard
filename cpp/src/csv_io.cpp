#include "fraudguard/engine.hpp"
#include "fraudguard/csv_io.hpp"

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace fraudguard {
namespace {

const std::vector<std::string> kHeader = {
    "transaction_id", "client_id", "timestamp", "amount", "currency",
    "country", "merchant_category", "device_id"};
const std::vector<std::string> kResultsHeader = {
    "transaction_id", "client_id", "timestamp", "amount", "currency",
    "risk_score", "decision", "risk_factors", "profile_status", "processing_status"};
const std::vector<std::string> kAlertsHeader = {
    "transaction_id", "client_id", "timestamp", "amount", "currency",
    "risk_score", "decision", "risk_factors"};
const std::vector<std::string> kErrorsHeader = {
    "source_file", "line_number", "transaction_id", "error_code", "message"};

struct CsvRecord {
    std::vector<std::string> fields;
    std::size_t line_number = 1;
};
struct CsvParseResult {
    std::vector<CsvRecord> records;
    std::string error;
    std::size_t error_line = 1;
};
std::string trim(const std::string& value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) return {};
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::string fileName(const std::filesystem::path& path) {
    return path.filename().empty() ? path.string() : path.filename().string();
}

CsvParseResult parseCsvText(std::string text) {
    // Strip a UTF-8 BOM if present.
    if (text.size() >= 3 && static_cast<unsigned char>(text[0]) == 0xEF &&
        static_cast<unsigned char>(text[1]) == 0xBB &&
        static_cast<unsigned char>(text[2]) == 0xBF) {
        text.erase(0, 3);
    }

    CsvParseResult result;
    CsvRecord record;
    std::string field;
    bool in_quotes = false;
    bool quote_closed = false;
    bool record_has_content = false;
    std::size_t physical_line = 1;
    std::size_t record_start_line = 1;

    auto finish_field = [&]() {
        record.fields.push_back(field);
        field.clear();
        quote_closed = false;
    };
    auto finish_record = [&]() {
        finish_field();
        record.line_number = record_start_line;
        if (!(record.fields.size() == 1 && record.fields.front().empty() && !record_has_content)) {
            result.records.push_back(record);
        }
        record = CsvRecord{};
        record_has_content = false;
        record_start_line = physical_line + 1;
    };

    for (std::size_t i = 0; i < text.size(); ++i) {
        const char c = text[i];
        if (in_quotes) {
            if (c == '"') {
                if (i + 1 < text.size() && text[i + 1] == '"') {
                    field.push_back('"');
                    ++i;
                } else {
                    in_quotes = false;
                    quote_closed = true;
                }
            } else if (c == '\n') {
                field.push_back('\n');
                ++physical_line;
            } else if (c == '\r') {
                if (i + 1 < text.size() && text[i + 1] == '\n') {
                    field.push_back('\n');
                    ++i;
                } else {
                    field.push_back('\n');
                }
                ++physical_line;
            } else {
                field.push_back(c);
            }
            record_has_content = true;
            continue;
        }

        if (quote_closed && c != ',' && c != '\n' && c != '\r' && c != ' ' && c != '\t') {
            result.error = "После закрывающей кавычки ожидались разделитель или конец строки";
            result.error_line = physical_line;
            return result;
        }
        if (c == '"') {
            if (!field.empty() || quote_closed) {
                result.error = "Кавычка встретилась внутри неэкранированного поля";
                result.error_line = physical_line;
                return result;
            }
            in_quotes = true;
            record_has_content = true;
        } else if (c == ',' ) {
            finish_field();
            record_has_content = true;
        } else if (c == '\n' || c == '\r') {
            if (c == '\r' && i + 1 < text.size() && text[i + 1] == '\n') ++i;
            finish_record();
            ++physical_line;
            record_start_line = physical_line;
        } else if (!quote_closed || (c != ' ' && c != '\t')) {
            field.push_back(c);
            record_has_content = true;
        }
    }
    if (in_quotes) {
        result.error = "Незакрытая кавычка в CSV";
        result.error_line = record_start_line;
        return result;
    }
    if (record_has_content || !field.empty() || !record.fields.empty()) {
        finish_field();
        record.line_number = record_start_line;
        result.records.push_back(record);
    }
    return result;
}

CsvParseResult readCsv(const std::filesystem::path& path, std::string& error) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        error = "Не удалось открыть файл";
        return {};
    }
    std::ostringstream buffer;
    buffer << input.rdbuf();
    if (input.bad()) {
        error = "Ошибка чтения файла";
        return {};
    }
    return parseCsvText(buffer.str());
}

bool validateHeader(const CsvRecord& header) {
    if (header.fields.size() != kHeader.size()) return false;
    for (std::size_t i = 0; i < kHeader.size(); ++i) {
        if (trim(header.fields[i]) != kHeader[i]) return false;
    }
    return true;
}

bool parseAmount(const std::string& text, long double& amount) {
    const std::string value = trim(text);
    if (value.empty()) return false;
    char* end = nullptr;
    errno = 0;
    const long double parsed = std::strtold(value.c_str(), &end);
    if (errno == ERANGE || end == value.c_str() || *end != '\0' || !std::isfinite(parsed) || parsed <= 0.0L) {
        return false;
    }
    amount = parsed;
    return true;
}

bool parseTransaction(const CsvRecord& record, Transaction& tx,
                      std::string& code, std::string& message) {
    if (record.fields.size() != kHeader.size()) {
        code = "CSV_COLUMN_COUNT";
        message = "Число полей не соответствует ожидаемой схеме из 8 колонок";
        return false;
    }
    tx.transaction_id = trim(record.fields[0]);
    tx.client_id = trim(record.fields[1]);
    tx.timestamp_text = trim(record.fields[2]);
    tx.amount_text = trim(record.fields[3]);
    tx.currency = trim(record.fields[4]);
    tx.country = trim(record.fields[5]);
    tx.merchant_category = trim(record.fields[6]);
    tx.device_id = trim(record.fields[7]);
    tx.line_number = record.line_number;

    const std::vector<std::string> required = {
        tx.transaction_id, tx.client_id, tx.timestamp_text, tx.amount_text,
        tx.currency, tx.country, tx.merchant_category, tx.device_id};
    if (std::any_of(required.begin(), required.end(), [](const std::string& v) { return v.empty(); })) {
        code = "REQUIRED_FIELD_EMPTY";
        message = "Одно или несколько обязательных полей пусты";
        return false;
    }
    if (!parseIso8601(tx.timestamp_text, tx.timestamp_epoch_milliseconds)) {
        code = "INVALID_TIMESTAMP";
        message = "Дата должна соответствовать ISO 8601 и содержать часовой пояс";
        return false;
    }
    if (!parseAmount(tx.amount_text, tx.amount)) {
        code = "INVALID_AMOUNT";
        message = "Сумма должна быть конечным числом строго больше нуля";
        return false;
    }
    if (tx.currency.size() != 3 || !std::all_of(tx.currency.begin(), tx.currency.end(),
            [](unsigned char c) { return c >= 'A' && c <= 'Z'; })) {
        code = "INVALID_CURRENCY";
        message = "Валюта должна быть трёхбуквенным кодом в верхнем регистре";
        return false;
    }
    return true;
}

std::string escapeCsv(const std::string& value) {
    if (value.find_first_of(",\"\r\n") == std::string::npos) return value;
    std::string escaped = "\"";
    for (char c : value) {
        if (c == '"') escaped += "\"\"";
        else escaped += c;
    }
    escaped += '"';
    return escaped;
}

void writeCsvRow(std::ostream& output, const std::vector<std::string>& fields) {
    for (std::size_t i = 0; i < fields.size(); ++i) {
        if (i) output << ',';
        output << escapeCsv(fields[i]);
    }
    output << '\n';
}

std::string factorCodes(const std::vector<RiskFactor>& factors) {
    std::ostringstream output;
    for (std::size_t i = 0; i < factors.size(); ++i) {
        if (i) output << ';';
        output << factors[i].code;
    }
    return output.str();
}

bool writeReportsInternal(const std::filesystem::path& out_dir,
                  const std::vector<ScoredTransaction>& results,
                  const std::vector<ProcessingError>& errors) {
    std::error_code ec;
    std::filesystem::create_directories(out_dir, ec);
    if (ec) {
        std::cerr << "Не удалось создать каталог отчётов: " << out_dir << " (" << ec.message() << ")\n";
        return false;
    }
    std::ofstream results_file(out_dir / "results.csv", std::ios::binary);
    std::ofstream alerts_file(out_dir / "alerts.csv", std::ios::binary);
    std::ofstream errors_file(out_dir / "errors.csv", std::ios::binary);
    if (!results_file || !alerts_file || !errors_file) {
        std::cerr << "Не удалось создать один или несколько отчётов в " << out_dir << '\n';
        return false;
    }
    writeCsvRow(results_file, kResultsHeader);
    writeCsvRow(alerts_file, kAlertsHeader);
    writeCsvRow(errors_file, kErrorsHeader);

    std::size_t alert_count = 0;
    for (const auto& result : results) {
        const auto& tx = result.transaction;
        const std::string codes = factorCodes(result.factors);
        writeCsvRow(results_file, {tx.transaction_id, tx.client_id, tx.timestamp_text,
            tx.amount_text, tx.currency, std::to_string(result.risk_score), result.decision,
            codes, toString(result.profile_status), "OK"});
        if (result.decision == "REVIEW" || result.decision == "BLOCK") {
            writeCsvRow(alerts_file, {tx.transaction_id, tx.client_id, tx.timestamp_text,
                tx.amount_text, tx.currency, std::to_string(result.risk_score), result.decision, codes});
            ++alert_count;
        }
    }
    for (const auto& error : errors) {
        writeCsvRow(errors_file, {error.source_file, std::to_string(error.line_number),
            error.transaction_id, error.error_code, error.message});
    }
    results_file.flush(); alerts_file.flush(); errors_file.flush();
    const bool ok = results_file.good() && alerts_file.good() && errors_file.good();
    if (!ok) std::cerr << "Ошибка записи одного или нескольких CSV-отчётов\n";
    return ok;
}

bool loadTransactionsInternal(const std::filesystem::path& path,
                      std::vector<Transaction>& transactions,
                      std::unordered_set<std::string>& seen_ids,
                      std::vector<ProcessingError>& errors) {
    std::string open_error;
    CsvParseResult parsed = readCsv(path, open_error);
    if (!open_error.empty()) {
        errors.push_back({fileName(path), 0, "", "FILE_READ", open_error});
        return false;
    }
    if (!parsed.error.empty()) {
        errors.push_back({fileName(path), parsed.error_line, "", "CSV_PARSE_ERROR", parsed.error});
        return false;
    }
    if (parsed.records.empty() || !validateHeader(parsed.records.front())) {
        errors.push_back({fileName(path), parsed.records.empty() ? 1 : parsed.records.front().line_number,
                          "", "FILE_SCHEMA", "Заголовок CSV не соответствует ожидаемым 8 колонкам"});
        return false;
    }
    for (std::size_t i = 1; i < parsed.records.size(); ++i) {
        const CsvRecord& record = parsed.records[i];
        Transaction tx;
        std::string code, message;
        if (!parseTransaction(record, tx, code, message)) {
            errors.push_back({fileName(path), record.line_number,
                record.fields.empty() ? "" : trim(record.fields.front()), code, message});
            continue;
        }
        if (seen_ids.find(tx.transaction_id) != seen_ids.end()) {
            errors.push_back({fileName(path), record.line_number, tx.transaction_id,
                              "DUPLICATE_TRANSACTION_ID", "Идентификатор транзакции уже встречался"});
            continue;
        }
        seen_ids.insert(tx.transaction_id);
        transactions.push_back(std::move(tx));
    }
    return true;
}


}  // namespace


bool loadTransactions(const std::filesystem::path& path,
                      std::vector<Transaction>& transactions,
                      std::unordered_set<std::string>& seen_ids,
                      std::vector<ProcessingError>& errors) {
    return loadTransactionsInternal(path, transactions, seen_ids, errors);
}

bool writeReports(const std::filesystem::path& out_dir,
                  const std::vector<ScoredTransaction>& results,
                  const std::vector<ProcessingError>& errors) {
    return writeReportsInternal(out_dir, results, errors);
}

}  // namespace fraudguard
