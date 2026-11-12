package fraudguard.ui

import fraudguard.engine.ScoringEngine
import fraudguard.io.ReportWriter
import fraudguard.model.AnalysisResult
import fraudguard.model.LiveTransactionRow
import fraudguard.model.ScoredTransaction
import fraudguard.service.FraudGuardService
import fraudguard.service.ProjectPaths
import java.awt.BorderLayout
import java.awt.Desktop
import java.awt.Dimension
import java.awt.FlowLayout
import java.awt.GridLayout
import java.nio.file.Files
import java.nio.file.Path
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import javax.swing.BorderFactory
import javax.swing.JButton
import javax.swing.JFileChooser
import javax.swing.JFrame
import javax.swing.JLabel
import javax.swing.JOptionPane
import javax.swing.JPanel
import javax.swing.JScrollPane
import javax.swing.JSpinner
import javax.swing.JTabbedPane
import javax.swing.JTable
import javax.swing.JTextArea
import javax.swing.JTextField
import javax.swing.SpinnerNumberModel
import javax.swing.SwingConstants
import javax.swing.SwingWorker
import javax.swing.Timer
import javax.swing.UIManager
import javax.swing.table.DefaultTableModel

class FraudGuardFrame : JFrame("FraudGuard — анти-фрод мониторинг") {
    private val projectRoot = ProjectPaths.findProjectRoot()
    private val transactionsField = JTextField(projectRoot.resolve("data/transactions.csv").toString(), 48)
    private val historyField = JTextField(projectRoot.resolve("data/history.csv").toString(), 48)
    private val outputField = JTextField(projectRoot.resolve("reports-kotlin").toString(), 48)
    private val intervalSpinner = JSpinner(SpinnerNumberModel(800, 100, 5000, 100))

    private val startButton = JButton("Старт ленты")
    private val pauseButton = JButton("Пауза")
    private val resetButton = JButton("Сбросить")
    private val cppButton = JButton("Запустить C++ batch")
    private val approveButton = JButton("Одобрить выбранную")
    private val rejectButton = JButton("Отклонить выбранную")
    private val detailsButton = JButton("Детали")

    private val statusLabel = JLabel("Готов к запуску")
    private val processedLabel = metricLabel("Обработано: 0")
    private val reviewLabel = metricLabel("На проверке: 0")
    private val blockedLabel = metricLabel("Заблокировано: 0")

    private val feedModel = ReadOnlyTableModel(arrayOf(
        "Время", "Транзакция", "Клиент", "Сумма", "Валюта", "Риск", "Рекомендация", "Статус", "Факторы риска"
    ))
    private val reviewModel = ReadOnlyTableModel(arrayOf("Транзакция", "Клиент", "Сумма", "Риск", "Рекомендация", "Факторы риска"))
    private val feedTable = JTable(feedModel)
    private val reviewTable = JTable(reviewModel)
    private val logArea = JTextArea(5, 100)

    private var analysis: AnalysisResult? = null
    private val liveRows = mutableListOf<LiveTransactionRow>()
    private var nextIndex = 0
    private var timer: Timer? = null
    private var loading = false
    private var feedFinished = false

    init {
        defaultCloseOperation = EXIT_ON_CLOSE
        minimumSize = Dimension(1050, 700)
        size = Dimension(1320, 850)
        setLocationRelativeTo(null)
        buildUi()
        installActions()
        appendLog("FraudGuard запущен в демонстрационном режиме. Все транзакции синтетические.")
        appendLog("Корень проекта: $projectRoot")
    }

    private fun buildUi() {
        layout = BorderLayout(8, 8)
        (rootPane as javax.swing.JComponent).border = BorderFactory.createEmptyBorder(10, 10, 10, 10)

        val header = JPanel(BorderLayout(8, 6))
        val title = JLabel("FraudGuard  |  Анти-фрод скоринг-движок")
        title.font = title.font.deriveFont(22f)
        val subtitle = JLabel("Демо-поток транзакций · ручная проверка · пакетный запуск C++")
        subtitle.horizontalAlignment = SwingConstants.RIGHT
        val titleRow = JPanel(BorderLayout())
        titleRow.add(title, BorderLayout.WEST)
        titleRow.add(subtitle, BorderLayout.EAST)
        header.add(titleRow, BorderLayout.NORTH)

        val filePanel = JPanel(GridLayout(3, 1, 4, 4))
        filePanel.border = BorderFactory.createTitledBorder("Источники данных и отчёты")
        filePanel.add(pathRow("Транзакции", transactionsField, "Выбрать CSV") { chooseFile(transactionsField) })
        filePanel.add(pathRow("История", historyField, "Выбрать CSV") { chooseOptionalHistory() })
        filePanel.add(pathRow("Папка отчётов", outputField, "Выбрать папку") { chooseDirectory(outputField) })
        header.add(filePanel, BorderLayout.CENTER)

        val controls = JPanel(FlowLayout(FlowLayout.LEFT, 8, 4))
        controls.add(startButton)
        controls.add(pauseButton)
        controls.add(resetButton)
        controls.add(JLabel("Интервал (мс):"))
        intervalSpinner.preferredSize = Dimension(85, intervalSpinner.preferredSize.height)
        controls.add(intervalSpinner)
        controls.add(cppButton)
        controls.add(JLabel("  "))
        controls.add(statusLabel)
        header.add(controls, BorderLayout.SOUTH)
        add(header, BorderLayout.NORTH)

        val metrics = JPanel(FlowLayout(FlowLayout.LEFT, 18, 4))
        metrics.add(processedLabel)
        metrics.add(reviewLabel)
        metrics.add(blockedLabel)

        val feedPanel = JPanel(BorderLayout(4, 4))
        feedPanel.add(metrics, BorderLayout.NORTH)
        feedPanel.add(JScrollPane(feedTable), BorderLayout.CENTER)
        val feedHint = JLabel("Лента воспроизводит строки CSV постепенно. Скоринг рассчитан теми же правилами, что и C++.")
        feedPanel.add(feedHint, BorderLayout.SOUTH)

        val reviewPanel = JPanel(BorderLayout(4, 4))
        reviewPanel.add(JScrollPane(reviewTable), BorderLayout.CENTER)
        val reviewControls = JPanel(FlowLayout(FlowLayout.LEFT, 8, 4))
        reviewControls.add(approveButton)
        reviewControls.add(rejectButton)
        reviewControls.add(detailsButton)
        reviewPanel.add(reviewControls, BorderLayout.SOUTH)

        val logPanel = JPanel(BorderLayout(4, 4))
        logPanel.border = BorderFactory.createTitledBorder("Журнал событий")
        logArea.isEditable = false
        logArea.lineWrap = true
        logArea.wrapStyleWord = true
        logPanel.add(JScrollPane(logArea), BorderLayout.CENTER)
        logPanel.preferredSize = Dimension(1000, 135)

        val tabs = JTabbedPane()
        tabs.addTab("Живая лента", feedPanel)
        tabs.addTab("Очередь REVIEW", reviewPanel)
        val mainPanel = JPanel(BorderLayout(6, 6))
        mainPanel.add(tabs, BorderLayout.CENTER)
        mainPanel.add(logPanel, BorderLayout.SOUTH)
        add(mainPanel, BorderLayout.CENTER)

        pauseButton.isEnabled = false
        approveButton.isEnabled = false
        rejectButton.isEnabled = false
        detailsButton.isEnabled = false
    }

    private fun pathRow(label: String, field: JTextField, buttonText: String, action: () -> Unit): JPanel {
        val panel = JPanel(BorderLayout(8, 0))
        val labelComponent = JLabel(label)
        labelComponent.preferredSize = Dimension(105, labelComponent.preferredSize.height)
        panel.add(labelComponent, BorderLayout.WEST)
        panel.add(field, BorderLayout.CENTER)
        val button = JButton(buttonText)
        button.addActionListener { action() }
        panel.add(button, BorderLayout.EAST)
        return panel
    }

    private fun installActions() {
        startButton.addActionListener { startSimulation() }
        pauseButton.addActionListener { togglePause() }
        resetButton.addActionListener { resetSimulation() }
        approveButton.addActionListener { decideSelectedReview(approve = true) }
        rejectButton.addActionListener { decideSelectedReview(approve = false) }
        detailsButton.addActionListener { showSelectedReviewDetails() }
        cppButton.addActionListener { runCppBatch() }
    }

    private fun chooseFile(field: JTextField) {
        val chooser = JFileChooser(resolvePath(field.text).parent?.toFile())
        chooser.dialogTitle = "Выберите CSV-файл"
        if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
            field.text = chooser.selectedFile.absolutePath
        }
    }

    private fun chooseOptionalHistory() {
        val chooser = JFileChooser(resolvePath(historyField.text).parent?.toFile())
        chooser.dialogTitle = "Выберите историю клиентов (Cancel — без истории)"
        if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
            historyField.text = chooser.selectedFile.absolutePath
        } else if (chooser.dialogType == JFileChooser.OPEN_DIALOG) {
            // Leave the current path unchanged; blank can be entered to disable history.
        }
    }

    private fun chooseDirectory(field: JTextField) {
        val chooser = JFileChooser(resolvePath(field.text).toFile())
        chooser.dialogTitle = "Выберите папку"
        chooser.fileSelectionMode = JFileChooser.DIRECTORIES_ONLY
        chooser.isAcceptAllFileFilterUsed = false
        if (chooser.showOpenDialog(this) == JFileChooser.APPROVE_OPTION) {
            field.text = chooser.selectedFile.absolutePath
        }
    }

    private fun resolvePath(raw: String): Path {
        val path = Path.of(raw.trim())
        return if (path.isAbsolute) path.normalize() else projectRoot.resolve(path).normalize()
    }

    private fun startSimulation() {
        if (loading) return
        val transactionsPath = resolvePath(transactionsField.text)
        val historyPath = historyField.text.trim().takeIf { it.isNotEmpty() }?.let { resolvePath(it) }
        val outputPath = resolvePath(outputField.text)
        if (!Files.exists(transactionsPath)) {
            JOptionPane.showMessageDialog(this, "Не найден файл транзакций:\n$transactionsPath", "Нет входного файла", JOptionPane.WARNING_MESSAGE)
            return
        }

        stopTimer()
        loading = true
        feedFinished = false
        startButton.isEnabled = false
        pauseButton.isEnabled = false
        statusLabel.text = "Загрузка и расчёт..."
        appendLog("Загружаю транзакции и рассчитываю скоринг...")

        val worker = object : SwingWorker<AnalysisResult, Void>() {
            override fun doInBackground(): AnalysisResult = FraudGuardService.analyze(transactionsPath, historyPath, outputPath)

            override fun done() {
                loading = false
                startButton.isEnabled = true
                try {
                    analysis = get()
                    liveRows.clear()
                    feedModel.setRowCount(0)
                    reviewModel.setRowCount(0)
                    nextIndex = 0
                    val result = requireNotNull(analysis)
                    if (!result.currentFileLoaded) {
                        statusLabel.text = "Входной CSV не загружен"
                        appendLog("Входной файл не удалось прочитать. См. ${outputPath.resolve("errors.csv")}")
                        JOptionPane.showMessageDialog(this@FraudGuardFrame, "Не удалось загрузить входной CSV. Проверьте файл ${outputPath.resolve("errors.csv")} и путь к источнику.", "Ошибка загрузки", JOptionPane.ERROR_MESSAGE)
                        updateMetrics()
                        return
                    }
                    appendLog("Исторических транзакций: ${result.historyCount}; валидных новых: ${result.scoredTransactions.size}; ошибок строк/файлов: ${result.errors.size}.")
                    appendLog("Пакетные отчёты записаны в: $outputPath")
                    if (result.errors.isNotEmpty()) appendLog("Есть отклонённые строки. Откройте errors.csv для причин.")
                    if (result.scoredTransactions.isEmpty()) {
                        statusLabel.text = "Нет валидных транзакций для воспроизведения"
                        feedFinished = true
                        updateMetrics()
                        return
                    }
                    pauseButton.isEnabled = true
                    pauseButton.text = "Пауза"
                    statusLabel.text = "Поток запущен"
                    timer = Timer((intervalSpinner.value as Number).toInt()) { emitNextTransaction() }
                    timer?.start()
                } catch (ex: Exception) {
                    statusLabel.text = "Ошибка запуска"
                    appendLog("Ошибка: ${ex.cause?.message ?: ex.message}")
                    JOptionPane.showMessageDialog(this@FraudGuardFrame, ex.cause?.message ?: ex.message, "Ошибка", JOptionPane.ERROR_MESSAGE)
                }
            }
        }
        worker.execute()
    }

    private fun emitNextTransaction() {
        val results = analysis?.scoredTransactions.orEmpty()
        if (nextIndex >= results.size) {
            stopTimer()
            feedFinished = true
            pauseButton.isEnabled = false
            pauseButton.text = "Пауза"
            statusLabel.text = "Поток завершён · можно обработать очередь REVIEW"
            appendLog("Демонстрационный поток завершён. Все решения оператора доступны в operator-decisions.csv.")
            saveOperatorDecisions()
            return
        }
        timer?.delay = (intervalSpinner.value as Number).toInt()
        val scored = results[nextIndex++]
        val initialStatus = when (scored.decision) {
            "APPROVE" -> "AUTO_APPROVED"
            "BLOCK" -> "AUTO_BLOCKED"
            else -> "PENDING_REVIEW"
        }
        val liveRow = LiveTransactionRow(scored, initialStatus)
        liveRows += liveRow
        feedModel.addRow(feedRowValues(liveRow))
        refreshReviewQueue()
        updateMetrics()
        saveOperatorDecisions()
        appendLog("${scored.transaction.transactionId}: риск ${scored.riskScore}, рекомендация ${scored.decision} → $initialStatus")
    }

    private fun togglePause() {
        val activeTimer = timer ?: return
        if (activeTimer.isRunning) {
            activeTimer.stop()
            pauseButton.text = "Продолжить"
            statusLabel.text = "Пауза"
            appendLog("Поток приостановлен пользователем.")
        } else if (!feedFinished && nextIndex < analysis?.scoredTransactions.orEmpty().size) {
            activeTimer.delay = (intervalSpinner.value as Number).toInt()
            activeTimer.start()
            pauseButton.text = "Пауза"
            statusLabel.text = "Поток запущен"
            appendLog("Поток продолжен.")
        }
    }

    private fun resetSimulation() {
        stopTimer()
        analysis = null
        liveRows.clear()
        nextIndex = 0
        loading = false
        feedFinished = false
        feedModel.setRowCount(0)
        reviewModel.setRowCount(0)
        pauseButton.isEnabled = false
        pauseButton.text = "Пауза"
        startButton.isEnabled = true
        statusLabel.text = "Готов к запуску"
        updateMetrics()
        appendLog("Лента сброшена. Для повторного запуска нажмите «Старт ленты».")
    }

    private fun stopTimer() {
        timer?.stop()
        timer = null
    }

    private fun decideSelectedReview(approve: Boolean) {
        val selectedViewRow = reviewTable.selectedRow
        if (selectedViewRow < 0) {
            JOptionPane.showMessageDialog(this, "Сначала выберите транзакцию в очереди REVIEW.", "Нет выбора", JOptionPane.INFORMATION_MESSAGE)
            return
        }
        val txId = reviewModel.getValueAt(selectedViewRow, 0).toString()
        val row = liveRows.firstOrNull { it.scored.transaction.transactionId == txId && it.workflowStatus == "PENDING_REVIEW" }
        if (row == null) {
            refreshReviewQueue()
            return
        }
        row.workflowStatus = if (approve) "APPROVED_BY_OPERATOR" else "REJECTED_BY_OPERATOR"
        row.reviewedAt = OffsetDateTime.now().format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)
        appendLog("Оператор ${if (approve) "ОДОБРИЛ" else "ОТКЛОНИЛ"} ${row.scored.transaction.transactionId}; рекомендация движка была ${row.scored.decision}.")
        refreshFeedTable()
        refreshReviewQueue()
        updateMetrics()
        saveOperatorDecisions()
    }

    private fun showSelectedReviewDetails() {
        val selectedRow = reviewTable.selectedRow
        if (selectedRow < 0) {
            JOptionPane.showMessageDialog(this, "Сначала выберите транзакцию в очереди REVIEW.", "Нет выбора", JOptionPane.INFORMATION_MESSAGE)
            return
        }
        val txId = reviewModel.getValueAt(selectedRow, 0).toString()
        val row = liveRows.firstOrNull { it.scored.transaction.transactionId == txId } ?: return
        val tx = row.scored.transaction
        val factors = row.scored.factors.joinToString("\n") { "• ${it.code}: +${it.points}" }.ifEmpty { "Факторы риска не сработали" }
        val message = "Транзакция: ${tx.transactionId}\nКлиент: ${tx.clientId}\n" +
            "Сумма: ${tx.amountText} ${tx.currency}\nВремя: ${tx.timestampText}\n" +
            "Страна: ${tx.country}\nКатегория: ${tx.merchantCategory}\nУстройство: ${tx.deviceId}\n\n" +
            "Риск-скор: ${row.scored.riskScore}/100\nРекомендация: ${row.scored.decision}\n\nФакторы:\n$factors"
        JOptionPane.showMessageDialog(this, message, "Детали ${tx.transactionId}", JOptionPane.INFORMATION_MESSAGE)
    }

    private fun refreshReviewQueue() {
        reviewModel.setRowCount(0)
        liveRows.filter { it.workflowStatus == "PENDING_REVIEW" }.forEach { row ->
            val tx = row.scored.transaction
            reviewModel.addRow(arrayOf(
                tx.transactionId, tx.clientId, "${tx.amountText} ${tx.currency}",
                row.scored.riskScore, row.scored.decision, row.scored.riskFactorsText.ifEmpty { "—" }
            ))
        }
        val hasSelection = reviewModel.rowCount > 0
        approveButton.isEnabled = hasSelection
        rejectButton.isEnabled = hasSelection
        detailsButton.isEnabled = hasSelection
    }

    private fun refreshFeedTable() {
        feedModel.setRowCount(0)
        liveRows.forEach { feedModel.addRow(feedRowValues(it)) }
    }

    private fun feedRowValues(row: LiveTransactionRow): Array<Any> {
        val tx = row.scored.transaction
        return arrayOf(
            tx.timestampText, tx.transactionId, tx.clientId, tx.amountText, tx.currency,
            row.scored.riskScore, row.scored.decision, row.workflowStatus,
            row.scored.riskFactorsText.ifEmpty { "—" }
        )
    }

    private fun updateMetrics() {
        processedLabel.text = "Обработано: ${liveRows.size}"
        reviewLabel.text = "На проверке: ${liveRows.count { it.workflowStatus == "PENDING_REVIEW" }}"
        blockedLabel.text = "Блокировки: ${liveRows.count { it.workflowStatus == "AUTO_BLOCKED" || it.workflowStatus == "REJECTED_BY_OPERATOR" }}"
    }

    private fun saveOperatorDecisions() {
        try {
            ReportWriter.writeOperatorDecisions(resolvePath(outputField.text), liveRows)
        } catch (ex: Exception) {
            appendLog("Не удалось сохранить журнал решений: ${ex.message}")
        }
    }

    private fun runCppBatch() {
        if (loading) return
        val executable = listOf(
            projectRoot.resolve("cpp/build/Release/fraudguard.exe"),
            projectRoot.resolve("cpp/build/fraudguard.exe"),
            projectRoot.resolve("cpp/build/Release/fraudguard"),
            projectRoot.resolve("cpp/build/fraudguard")
        ).firstOrNull { Files.isRegularFile(it) }
        if (executable == null) {
            JOptionPane.showMessageDialog(
                this,
                "Не найден собранный C++-движок. Сначала соберите его из корня проекта:\n\ncmake --build cpp/build --config Release",
                "C++-движок не найден", JOptionPane.WARNING_MESSAGE
            )
            return
        }
        val transactionsPath = resolvePath(transactionsField.text)
        val historyPath = historyField.text.trim().takeIf { it.isNotEmpty() }?.let { resolvePath(it) }
        val cppOut = resolvePath(outputField.text).resolve("cpp-batch")
        val command = mutableListOf(executable.toAbsolutePath().toString(), "--transactions", transactionsPath.toString(), "--out-dir", cppOut.toString())
        if (historyPath != null && Files.exists(historyPath)) {
            command += listOf("--history", historyPath.toString())
        } else {
            command += "--no-history"
        }
        cppButton.isEnabled = false
        statusLabel.text = "Запуск C++ batch..."
        appendLog("Запускаю C++-движок: $executable")
        val worker = object : SwingWorker<Int, Void>() {
            override fun doInBackground(): Int {
                val process = ProcessBuilder(command).directory(projectRoot.toFile()).redirectErrorStream(true).start()
                // Drain stdout/stderr to avoid blocking if the child process writes enough output.
                process.inputStream.bufferedReader(Charsets.UTF_8).use { reader -> while (reader.readLine() != null) { /* consumed */ } }
                return process.waitFor()
            }
            override fun done() {
                cppButton.isEnabled = true
                try {
                    val exitCode = get()
                    statusLabel.text = if (exitCode == 0) "C++ batch завершён" else "C++ завершился с кодом $exitCode"
                    appendLog("C++ завершил работу с кодом $exitCode. Отчёты: $cppOut")
                    if (Files.exists(cppOut.resolve("results.csv"))) {
                        val open = JOptionPane.showConfirmDialog(this@FraudGuardFrame, "C++-отчёты созданы:\n$cppOut\n\nОткрыть папку?", "Готово", JOptionPane.YES_NO_OPTION)
                        if (open == JOptionPane.YES_OPTION && Desktop.isDesktopSupported()) Desktop.getDesktop().open(cppOut.toFile())
                    }
                } catch (ex: Exception) {
                    statusLabel.text = "Ошибка запуска C++"
                    appendLog("Ошибка при запуске C++: ${ex.cause?.message ?: ex.message}")
                    JOptionPane.showMessageDialog(this@FraudGuardFrame, ex.cause?.message ?: ex.message, "Ошибка C++", JOptionPane.ERROR_MESSAGE)
                }
            }
        }
        worker.execute()
    }

    private fun appendLog(message: String) {
        val time = java.time.LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm:ss"))
        logArea.append("[$time] $message\n")
        logArea.caretPosition = logArea.document.length
    }

    private fun metricLabel(text: String) = JLabel(text).apply {
        border = BorderFactory.createCompoundBorder(BorderFactory.createEtchedBorder(), BorderFactory.createEmptyBorder(5, 10, 5, 10))
        font = font.deriveFont(font.size + 1f)
    }

    private class ReadOnlyTableModel(columns: Array<String>) : DefaultTableModel(columns, 0) {
        override fun isCellEditable(row: Int, column: Int): Boolean = false
    }
}
