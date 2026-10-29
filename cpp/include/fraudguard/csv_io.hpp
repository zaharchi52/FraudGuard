#pragma once

#include "fraudguard/engine.hpp"

#include <filesystem>
#include <string>
#include <unordered_set>
#include <vector>

namespace fraudguard {

struct ProcessingError {
    std::string source_file;
    std::size_t line_number = 0;
    std::string transaction_id;
    std::string error_code;
    std::string message;
};

bool loadTransactions(const std::filesystem::path& path,
                      std::vector<Transaction>& transactions,
                      std::unordered_set<std::string>& seen_ids,
                      std::vector<ProcessingError>& errors);
bool writeReports(const std::filesystem::path& out_dir,
                  const std::vector<ScoredTransaction>& results,
                  const std::vector<ProcessingError>& errors);

}  // namespace fraudguard
