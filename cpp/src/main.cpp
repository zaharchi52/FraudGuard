#include "fraudguard/engine.hpp"

#include <iostream>
#include <string>

namespace {
void printUsage(const char* program) {
    std::cout << "Использование: " << program
              << " [--transactions FILE] [--history FILE | --no-history] [--out-dir DIR]\n\n"
              << "Значения по умолчанию при запуске из корня проекта:\n"
              << "  --transactions data/transactions.csv\n"
              << "  --history      data/history.csv\n"
              << "  --out-dir      reports\n";
}
}

int main(int argc, char* argv[]) {
    fraudguard::ProcessingOptions options;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            printUsage(argv[0]);
            return 0;
        } else if (arg == "--no-history") {
            options.use_history = false;
        } else if (arg == "--transactions" || arg == "--history" || arg == "--out-dir") {
            if (i + 1 >= argc) {
                std::cerr << "Ошибка: после " << arg << " нужно указать путь.\n";
                printUsage(argv[0]);
                return 2;
            }
            const std::string value = argv[++i];
            if (arg == "--transactions") options.transactions_path = value;
            else if (arg == "--history") { options.history_path = value; options.use_history = true; }
            else options.output_dir = value;
        } else {
            std::cerr << "Неизвестный аргумент: " << arg << '\n';
            printUsage(argv[0]);
            return 2;
        }
    }
    return fraudguard::run(options);
}
