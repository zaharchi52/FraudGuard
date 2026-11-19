package fraudguard.csv

import fraudguard.model.CsvReadResult
import fraudguard.model.CsvRecord
import fraudguard.model.LoadedTransactions
import fraudguard.model.ProcessingError
import fraudguard.model.TRANSACTION_HEADER
import fraudguard.model.Transaction
import java.math.BigDecimal
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/** Small RFC-4180-style CSV reader/writer; no third-party dependency is required. */
object CsvCodec {
    fun readRecords(path: Path): CsvReadResult {
        return try {
            parseText(Files.readString(path, StandardCharsets.UTF_8))
        } catch (ex: Exception) {
            CsvReadResult(emptyList(), ex.message ?: "Не удалось прочитать CSV-файл", 0)
        }
    }

    fun parseText(input: String): CsvReadResult {
        val text = input.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n')
        if (text.isEmpty()) return CsvReadResult(emptyList())

        val records = mutableListOf<CsvRecord>()
        val fields = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var fieldWasQuoted = false
        var quoteClosed = false
        var lineNumber = 1
        var recordStartLine = 1
        var i = 0

        fun finishField() {
            fields += field.toString()
            field.setLength(0)
            fieldWasQuoted = false
            quoteClosed = false
        }
        fun finishRecord() {
            finishField()
            if (!(fields.size == 1 && fields[0].isBlank())) {
                records += CsvRecord(recordStartLine, fields.toList())
            }
            fields.clear()
            recordStartLine = lineNumber + 1
        }

        while (i < text.length) {
            val ch = text[i]
            if (inQuotes) {
                when (ch) {
                    '"' -> {
                        if (i + 1 < text.length && text[i + 1] == '"') {
                            field.append('"')
                            i++
                        } else {
                            inQuotes = false
                            quoteClosed = true
                        }
                    }
                    '\n' -> {
                        field.append(ch)
                        lineNumber++
                    }
                    else -> field.append(ch)
                }
            } else {
                if (quoteClosed) {
                    when (ch) {
                        ',' -> finishField()
                        '\n' -> {
                            finishRecord()
                            lineNumber++
                            recordStartLine = lineNumber
                        }
                        ' ', '\t' -> Unit // Ignore whitespace after a closing quote, as C++ does.
                        else -> return CsvReadResult(emptyList(), "После закрывающей кавычки ожидались разделитель или конец строки", lineNumber)
                    }
                    i++
                    continue
                }
                when (ch) {
                    ',' -> finishField()
                    '\n' -> {
                        finishRecord()
                        lineNumber++
                        recordStartLine = lineNumber
                    }
                    '"' -> {
                        if (field.isNotEmpty() || fieldWasQuoted) {
                            return CsvReadResult(emptyList(), "Кавычка в неожиданной позиции", lineNumber)
                        }
                        inQuotes = true
                        fieldWasQuoted = true
                    }
                    else -> field.append(ch)
                }
            }
            i++
        }

        if (inQuotes) return CsvReadResult(emptyList(), "Незакрытая кавычка в CSV", recordStartLine)
        // A trailing newline already finalized the last record.
        if (field.isNotEmpty() || fields.isNotEmpty() || (text.isNotEmpty() && !text.endsWith('\n'))) {
            finishRecord()
        }
        return CsvReadResult(records)
    }

    fun loadTransactions(path: Path, seenIds: MutableSet<String>): LoadedTransactions {
        val sourceName = path.fileName?.toString() ?: path.toString()
        if (!Files.exists(path) || !Files.isRegularFile(path)) {
            return LoadedTransactions(
                emptyList(),
                listOf(ProcessingError(sourceName, 0, "", "FILE_READ", "Файл не найден или недоступен для чтения")),
                false
            )
        }

        val parsed = readRecords(path)
        if (parsed.errorMessage != null) {
            return LoadedTransactions(
                emptyList(),
                listOf(ProcessingError(sourceName, parsed.errorLine, "", "CSV_PARSE_ERROR", parsed.errorMessage)),
                false
            )
        }
        if (parsed.records.isEmpty() || parsed.records.first().fields.map { it.trim() } != TRANSACTION_HEADER) {
            val line = parsed.records.firstOrNull()?.lineNumber ?: 1
            return LoadedTransactions(
                emptyList(),
                listOf(ProcessingError(sourceName, line, "", "FILE_SCHEMA", "Заголовок CSV не соответствует ожидаемой схеме из 8 колонок")),
                false
            )
        }

        val transactions = mutableListOf<Transaction>()
        val errors = mutableListOf<ProcessingError>()
        for (record in parsed.records.drop(1)) {
            val values = record.fields.map { it.trim() }
            val transactionId = values.firstOrNull().orEmpty()
            if (values.size != TRANSACTION_HEADER.size) {
                errors += ProcessingError(sourceName, record.lineNumber, transactionId, "CSV_COLUMN_COUNT", "Число полей не соответствует ожидаемой схеме из 8 колонок")
                continue
            }
            val (tx, errorCode, message) = validateTransaction(values, record.lineNumber)
            if (tx == null) {
                errors += ProcessingError(sourceName, record.lineNumber, transactionId, errorCode, message)
                continue
            }
            if (!seenIds.add(tx.transactionId)) {
                errors += ProcessingError(sourceName, record.lineNumber, tx.transactionId, "DUPLICATE_TRANSACTION_ID", "Идентификатор транзакции уже встречался")
                continue
            }
            transactions += tx
        }
        return LoadedTransactions(transactions, errors, true)
    }

    private data class ValidationOutcome(
        val transaction: Transaction?,
        val errorCode: String = "",
        val message: String = ""
    )

    private fun validateTransaction(values: List<String>, lineNumber: Int): ValidationOutcome {
        val id = values[0]
        val client = values[1]
        val timestampText = values[2]
        val amountText = values[3]
        val currency = values[4]
        val country = values[5]
        val category = values[6]
        val device = values[7]
        if (values.any { it.isBlank() }) {
            return ValidationOutcome(null, "REQUIRED_FIELD_EMPTY", "Одно или несколько обязательных полей пусты")
        }
        val timestamp = try {
            OffsetDateTime.parse(timestampText, DateTimeFormatter.ISO_OFFSET_DATE_TIME).toInstant()
        } catch (_: DateTimeParseException) {
            return ValidationOutcome(null, "INVALID_TIMESTAMP", "Дата должна соответствовать ISO 8601 и содержать часовой пояс")
        }
        val amount = try {
            BigDecimal(amountText)
        } catch (_: NumberFormatException) {
            return ValidationOutcome(null, "INVALID_AMOUNT", "Сумма должна быть конечным числом строго больше нуля")
        }
        if (amount <= BigDecimal.ZERO || !amount.toDouble().isFinite()) {
            return ValidationOutcome(null, "INVALID_AMOUNT", "Сумма должна быть конечным числом строго больше нуля")
        }
        if (!currency.matches(Regex("[A-Z]{3}"))) {
            return ValidationOutcome(null, "INVALID_CURRENCY", "Валюта должна быть трёхбуквенным кодом в верхнем регистре")
        }
        return ValidationOutcome(
            Transaction(id, client, timestampText, amountText, currency, country, category, device, amount, timestamp, lineNumber)
        )
    }

    fun encodeRow(fields: List<String>): String = fields.joinToString(",") { escape(it) }

    fun escape(value: String): String {
        return if (value.any { it == ',' || it == '"' || it == '\r' || it == '\n' }) {
            "\"" + value.replace("\"", "\"\"") + "\""
        } else value
    }
}
