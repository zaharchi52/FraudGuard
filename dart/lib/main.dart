import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'csv_codec.dart';
import 'fraudguard_service.dart';
import 'models.dart';

void main() {
  runApp(const FraudGuardApp());
}

class FraudGuardApp extends StatelessWidget {
  const FraudGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF365CF5);
    return MaterialApp(
      title: 'FraudGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        fontFamily: 'Arial',
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF16233B), letterSpacing: -0.7),
          headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF16233B), letterSpacing: -0.4),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF16233B)),
          titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF25334D)),
          bodyMedium: TextStyle(fontSize: 13, color: Color(0xFF59677F), height: 1.4),
          bodySmall: TextStyle(fontSize: 11, color: Color(0xFF8290A6), height: 1.35),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: seed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF34435D),
            side: const BorderSide(color: Color(0xFFDCE3EF)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ),
      home: const FraudGuardDashboard(),
    );
  }
}

class FraudGuardDashboard extends StatefulWidget {
  const FraudGuardDashboard({super.key});

  @override
  State<FraudGuardDashboard> createState() => _FraudGuardDashboardState();
}

class _FraudGuardDashboardState extends State<FraudGuardDashboard> {
  String _transactionsCsv = '';
  String? _historyCsv;
  String _transactionsName = 'transactions.csv';
  String _historyName = 'history.csv';
  String _status = 'Загружаю демонстрационные данные';
  String _selectedReviewId = '';
  int _navigationIndex = 0;
  int _intervalMs = 800;
  int _nextIndex = 0;
  bool _isPlaying = false;
  bool _isPaused = false;
  bool _isBusy = false;
  bool _historyDisabled = false;
  String _feedFilter = 'Все';
  Timer? _timer;
  AnalysisBatch? _batch;
  final List<LiveTransactionRow> _liveRows = <LiveTransactionRow>[];

  @override
  void initState() {
    super.initState();
    _loadDemoData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadDemoData() async {
    try {
      final transactionData = await rootBundle.loadString('assets/data/transactions.csv');
      final historyData = await rootBundle.loadString('assets/data/history.csv');
      if (!mounted) return;
      setState(() {
        _resetStream(keepStatus: true);
        _transactionsCsv = transactionData;
        _historyCsv = historyData;
        _historyDisabled = false;
        _transactionsName = 'transactions.csv · демо';
        _historyName = 'history.csv · демо';
        _status = 'Демонстрационные данные готовы';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось загрузить демо-данные');
      _showMessage('Не удалось загрузить демонстрационные CSV: $error');
    }
  }

  Future<void> _pickTransactions() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (files.isEmpty) return;
      final content = utf8.decode(await files.first.readAsBytes());
      if (!mounted) return;
      setState(() {
        _transactionsCsv = content;
        _transactionsName = files.first.name;
        _resetStream(keepStatus: true);
        _status = 'Файл транзакций загружен';
      });
    } catch (error) {
      _showMessage('Не удалось прочитать CSV: $error');
    }
  }

  Future<void> _pickHistory() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (files.isEmpty) return;
      final content = utf8.decode(await files.first.readAsBytes());
      if (!mounted) return;
      setState(() {
        _historyCsv = content;
        _historyName = files.first.name;
        _historyDisabled = false;
        _resetStream(keepStatus: true);
        _status = 'История клиента загружена';
      });
    } catch (error) {
      _showMessage('Не удалось прочитать историю: $error');
    }
  }

  void _disableHistory() {
    setState(() {
      _historyCsv = null;
      _historyName = 'без истории';
      _historyDisabled = true;
      _resetStream(keepStatus: true);
      _status = 'Режим без истории · профили будут COLD_START';
    });
  }

  void _resetStream({bool keepStatus = false}) {
    _timer?.cancel();
    _timer = null;
    _batch = null;
    _liveRows.clear();
    _nextIndex = 0;
    _isPlaying = false;
    _isPaused = false;
    _selectedReviewId = '';
    if (!keepStatus) _status = 'Готов к запуску';
  }

  void _startStream() {
    if (_isBusy || _isPlaying) return;
    if (_isPaused && _batch != null) {
      _resumeStream();
      return;
    }
    if (_transactionsCsv.isEmpty) {
      _showMessage('Сначала выберите transactions.csv или загрузите демо-данные.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Выполняю валидацию и скоринг';
    });
    try {
      final batch = FraudGuardService.analyze(
        transactionsCsv: _transactionsCsv,
        transactionsFileName: _transactionsName,
        historyCsv: _historyDisabled ? null : _historyCsv,
        historyFileName: _historyName,
      );
      if (!batch.currentFileLoaded) {
        setState(() {
          _batch = batch;
          _isBusy = false;
          _status = 'Файл транзакций не прошёл проверку схемы';
        });
        return;
      }
      setState(() {
        _batch = batch;
        _liveRows.clear();
        _nextIndex = 0;
        _isBusy = false;
        _isPlaying = true;
        _isPaused = false;
        _status = 'Поток активен · ${batch.scoredTransactions.length} операций';
      });
      if (batch.scoredTransactions.isEmpty) {
        setState(() {
          _isPlaying = false;
          _status = 'В файле нет валидных транзакций';
        });
        return;
      }
      _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _emitNext());
    } catch (error) {
      setState(() {
        _isBusy = false;
        _isPlaying = false;
        _status = 'Ошибка анализа';
      });
      _showMessage('Ошибка анализа CSV: $error');
    }
  }

  void _emitNext() {
    final batch = _batch;
    if (batch == null || _nextIndex >= batch.scoredTransactions.length) {
      _finishStream();
      return;
    }
    final scored = batch.scoredTransactions[_nextIndex++];
    setState(() {
      _liveRows.insert(0, LiveTransactionRow(scored));
      if (scored.decision == 'REVIEW') {
        _selectedReviewId = scored.transaction.transactionId;
      }
    });
    if (_nextIndex >= batch.scoredTransactions.length) _finishStream();
  }

  void _finishStream() {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _isPaused = false;
      _status = 'Поток завершён · очередь REVIEW доступна';
    });
  }

  void _pauseStream() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _isPlaying = false;
      _isPaused = true;
      _status = 'Поток приостановлен';
    });
  }

  void _resumeStream() {
    if (_batch == null || _nextIndex >= _batch!.scoredTransactions.length) return;
    setState(() {
      _isPlaying = true;
      _isPaused = false;
      _status = 'Поток продолжен';
    });
    _timer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) => _emitNext());
  }

  void _reset() {
    setState(() {
      _resetStream();
    });
  }

  void _decide(String transactionId, {required bool approve}) {
    final row = _firstOrNull(_liveRows.where((item) => item.scored.transaction.transactionId == transactionId));
    if (row == null || !row.isPending) return;
    setState(() {
      row.workflowStatus = approve ? 'APPROVED_BY_OPERATOR' : 'REJECTED_BY_OPERATOR';
      row.reviewedAt = DateTime.now().toUtc().toIso8601String();
      _selectedReviewId = '';
      _status = approve ? 'Оператор одобрил $transactionId' : 'Оператор отклонил $transactionId';
    });
  }

  Future<void> _exportReport(String reportType) async {
    final batch = _batch;
    if (batch == null) {
      _showMessage('Сначала запустите анализ транзакций.');
      return;
    }
    final content = switch (reportType) {
      'results' => _buildResultsCsv(batch.scoredTransactions),
      'alerts' => _buildAlertsCsv(batch.scoredTransactions),
      'errors' => _buildErrorsCsv(batch.errors),
      'operator-decisions' => _buildOperatorCsv(_liveRows),
      _ => '',
    };
    final fileName = '$reportType.csv';
    try {
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (mounted) _showMessage('Файл $fileName подготовлен к сохранению.');
    } catch (error) {
      _showMessage('Не удалось сохранить отчёт: $error');
    }
  }

  String _buildResultsCsv(List<ScoredTransaction> rows) {
    final lines = <String>[CsvCodec.encodeRow(resultsHeader)];
    for (final row in rows) {
      final tx = row.transaction;
      lines.add(CsvCodec.encodeRow([
        tx.transactionId,
        tx.clientId,
        tx.timestampText,
        tx.amountText,
        tx.currency,
        row.riskScore.toString(),
        row.decision,
        row.riskFactorsText,
        row.profileStatus.csvValue,
        'OK',
      ]));
    }
    return '${lines.join('\n')}\n';
  }

  String _buildAlertsCsv(List<ScoredTransaction> rows) {
    final lines = <String>[CsvCodec.encodeRow(alertsHeader)];
    for (final row in rows.where((item) => item.decision == 'REVIEW' || item.decision == 'BLOCK')) {
      final tx = row.transaction;
      lines.add(CsvCodec.encodeRow([
        tx.transactionId,
        tx.clientId,
        tx.timestampText,
        tx.amountText,
        tx.currency,
        row.riskScore.toString(),
        row.decision,
        row.riskFactorsText,
      ]));
    }
    return '${lines.join('\n')}\n';
  }

  String _buildErrorsCsv(List<ProcessingError> rows) {
    final lines = <String>[CsvCodec.encodeRow(errorsHeader)];
    for (final row in rows) {
      lines.add(CsvCodec.encodeRow([
        row.sourceFile,
        row.lineNumber.toString(),
        row.transactionId,
        row.errorCode,
        row.message,
      ]));
    }
    return '${lines.join('\n')}\n';
  }

  String _buildOperatorCsv(List<LiveTransactionRow> rows) {
    final header = [
      'transaction_id', 'client_id', 'amount', 'currency', 'risk_score',
      'engine_decision', 'operator_decision', 'workflow_status', 'risk_factors', 'reviewed_at',
    ];
    final lines = <String>[CsvCodec.encodeRow(header)];
    for (final row in rows.reversed) {
      final tx = row.scored.transaction;
      final operatorDecision = switch (row.workflowStatus) {
        'APPROVED_BY_OPERATOR' => 'APPROVE',
        'REJECTED_BY_OPERATOR' => 'REJECT',
        _ => '',
      };
      lines.add(CsvCodec.encodeRow([
        tx.transactionId,
        tx.clientId,
        tx.amountText,
        tx.currency,
        row.scored.riskScore.toString(),
        row.scored.decision,
        operatorDecision,
        row.workflowStatus,
        row.scored.riskFactorsText,
        row.reviewedAt,
      ]));
    }
    return '${lines.join('\n')}\n';
  }

  Future<void> _compareWithFixture() async {
    final batch = _batch;
    if (batch == null) {
      _showMessage('Сначала запустите анализ.');
      return;
    }
    try {
      final expectedText = await rootBundle.loadString('assets/data/expected-results.csv');
      final expected = CsvCodec.parseText(expectedText);
      if (expected.errorMessage != null || expected.records.length < 2) {
        _showMessage('Не удалось прочитать эталонный файл.');
        return;
      }
      final expectedRows = <String, List<String>>{};
      for (final record in expected.records.skip(1)) {
        final fields = record.fields;
        if (fields.length >= 5) expectedRows[fields[0]] = fields;
      }
      var matched = 0;
      final mismatches = <String>[];
      for (final row in batch.scoredTransactions) {
        final exp = expectedRows[row.transaction.transactionId];
        final actual = [
          row.transaction.transactionId,
          row.riskScore.toString(),
          row.decision,
          row.riskFactorsText,
          row.profileStatus.csvValue,
        ];
        if (exp != null && _sameFields(actual, exp.take(5).toList())) {
          matched++;
        } else {
          mismatches.add(row.transaction.transactionId);
        }
      }
      final allMatched = mismatches.isEmpty && matched == expectedRows.length;
      if (!mounted) return;
      setState(() => _status = allMatched ? 'Сверка пройдена · $matched/${expectedRows.length}' : 'Сверка: $matched/${expectedRows.length}');
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(children: [
            Icon(allMatched ? Icons.verified_rounded : Icons.warning_amber_rounded,
                color: allMatched ? AppColors.green : AppColors.amber),
            const SizedBox(width: 10),
            Text(allMatched ? 'Результаты совпали' : 'Есть расхождения'),
          ]),
          content: Text(allMatched
              ? 'Все ${expectedRows.length} транзакций совпали с эталонным CSV по риск-скору, решению, факторам и статусу профиля.'
              : 'Совпало $matched из ${expectedRows.length}. Проверьте: ${mismatches.join(', ')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Закрыть'))],
        ),
      );
    } catch (error) {
      _showMessage('Ошибка сверки: $error');
    }
  }

  bool _sameFields(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  List<LiveTransactionRow> get _pendingRows =>
      _liveRows.where((row) => row.isPending).toList(growable: false);

  int get _blockedCount => _liveRows.where((row) => row.isBlocked).length;
  int get _approvedCount => _liveRows.where((row) =>
      row.workflowStatus == 'AUTO_APPROVED' || row.workflowStatus == 'APPROVED_BY_OPERATOR').length;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1060;
      return Scaffold(
        body: SafeArea(
          child: wide
              ? Row(children: [
                  SizedBox(width: 244, child: _buildSidebar()),
                  Expanded(child: Column(children: [
                    _buildTopBar(),
                    Expanded(child: _buildCurrentPage()),
                  ])),
                ])
              : Column(children: [
                  _buildTopBar(compact: true),
                  Expanded(child: _buildCurrentPage()),
                  NavigationBar(
                    selectedIndex: _navigationIndex,
                    onDestinationSelected: (value) => setState(() => _navigationIndex = value),
                    destinations: const [
                      NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), selectedIcon: Icon(Icons.monitor_heart), label: 'Мониторинг'),
                      NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Проверка'),
                      NavigationDestination(icon: Icon(Icons.folder_open_outlined), selectedIcon: Icon(Icons.folder_open), label: 'Отчёты'),
                    ],
                  ),
                ]),
        ),
      );
    });
  }

  Widget _buildSidebar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 11),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('FraudGuard', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18)),
            const Text('RISK OPERATIONS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 1.3)),
          ]),
        ]),
        const SizedBox(height: 38),
        const _SectionLabel('РАБОЧЕЕ ПРОСТРАНСТВО'),
        const SizedBox(height: 10),
        _NavItem(icon: Icons.monitor_heart_outlined, label: 'Мониторинг', selected: _navigationIndex == 0, onTap: () => setState(() => _navigationIndex = 0)),
        _NavItem(icon: Icons.fact_check_outlined, label: 'Очередь REVIEW', count: _pendingRows.length, selected: _navigationIndex == 1, onTap: () => setState(() => _navigationIndex = 1)),
        _NavItem(icon: Icons.folder_open_outlined, label: 'Отчёты', selected: _navigationIndex == 2, onTap: () => setState(() => _navigationIndex = 2)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFF4F7FF), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE4EAFE))),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, color: AppColors.blue, size: 19),
            SizedBox(height: 9),
            Text('Демонстрационный режим', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 12)),
            SizedBox(height: 4),
            Text('Используются синтетические CSV-данные. Реальные платежи не обрабатываются.', style: TextStyle(fontSize: 11, color: AppColors.muted, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 15),
        const Text('FraudGuard · учебный проект', style: TextStyle(fontSize: 10, color: AppColors.muted)),
      ]),
    );
  }

  Widget _buildTopBar({bool compact = false}) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 30),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (compact) ...[
          const Icon(Icons.shield_rounded, color: AppColors.blue, size: 23),
          const SizedBox(width: 9),
          Text('FraudGuard', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
        ] else ...[
          const Icon(Icons.circle, color: AppColors.green, size: 9),
          const SizedBox(width: 9),
          Text(_status, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const Spacer(),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFFFF7E8), borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0xFFF8E6BF))),
          child: const Row(children: [
            Icon(Icons.science_outlined, color: AppColors.amber, size: 14),
            SizedBox(width: 6),
            Text('SIMULATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF946314), letterSpacing: 0.7)),
          ]),
        ),
        const SizedBox(width: 12),
        CircleAvatar(radius: 17, backgroundColor: const Color(0xFFE9EEFF), child: const Text('OP', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.blue))),
      ]),
    );
  }

  Widget _buildCurrentPage() => switch (_navigationIndex) {
        0 => _buildMonitorPage(),
        1 => _buildReviewPage(),
        _ => _buildReportsPage(),
      };

  Widget _buildMonitorPage() {
    final batch = _batch;
    final filteredRows = _liveRows.where((row) {
      return switch (_feedFilter) {
        'На проверке' => row.isPending,
        'BLOCK' => row.scored.decision == 'BLOCK',
        _ => true,
      };
    }).toList(growable: false);

    return ListView(padding: const EdgeInsets.fromLTRB(26, 26, 26, 32), children: [
      _pageHeading('Мониторинг транзакций', 'Поток операций, скоринг и контроль решений в одном окне.'),
      const SizedBox(height: 22),
      _buildSourcePanel(),
      const SizedBox(height: 18),
      _buildControlPanel(),
      const SizedBox(height: 20),
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gap = 12.0;
        final cardWidth = (width - gap * 3) / 4;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          _MetricCard(width: cardWidth, label: 'Обработано', value: '${_liveRows.length}', icon: Icons.swap_horiz_rounded, tint: const Color(0xFFEAF0FF), accent: AppColors.blue, footnote: 'из ${batch?.scoredTransactions.length ?? 0} операций'),
          _MetricCard(width: cardWidth, label: 'На проверке', value: '${_pendingRows.length}', icon: Icons.manage_search_rounded, tint: const Color(0xFFFFF4DF), accent: AppColors.amber, footnote: 'ожидают решения оператора'),
          _MetricCard(width: cardWidth, label: 'Одобрено', value: '$_approvedCount', icon: Icons.check_circle_outline_rounded, tint: const Color(0xFFE6F7EF), accent: AppColors.green, footnote: 'автоматически и вручную'),
          _MetricCard(width: cardWidth, label: 'Блокировки', value: '$_blockedCount', icon: Icons.block_rounded, tint: const Color(0xFFFFEBEA), accent: AppColors.red, footnote: 'BLOCK и отклонённые'),
        ]);
      }),
      const SizedBox(height: 22),
      _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Живая лента', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 3),
              Text('Транзакции появляются постепенно по мере воспроизведения CSV.', style: Theme.of(context).textTheme.bodySmall),
            ])),
            DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _feedFilter,
              borderRadius: BorderRadius.circular(12),
              items: const ['Все', 'На проверке', 'BLOCK'].map((value) => DropdownMenuItem(value: value, child: Text(value, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (value) => setState(() => _feedFilter = value ?? 'Все'),
            )),
          ]),
          const SizedBox(height: 15),
          if (filteredRows.isEmpty)
            _emptyState(Icons.radar_rounded, 'Пока нет транзакций', 'Нажмите «Запустить поток», чтобы начать демонстрацию.')
          else
            _buildFeedTable(filteredRows),
        ]),
      ),
    ]);
  }

  Widget _buildSourcePanel() {
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Источники данных', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          TextButton.icon(onPressed: _loadDemoData, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Демо-набор')),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 700;
          final first = _FileSourceCard(
            title: 'Новые транзакции',
            fileName: _transactionsName,
            subtitle: 'Обязательный CSV · 8 колонок',
            icon: Icons.receipt_long_rounded,
            selected: _transactionsCsv.isNotEmpty,
            onPick: _pickTransactions,
          );
          final second = _FileSourceCard(
            title: 'История клиента',
            fileName: _historyName,
            subtitle: _historyDisabled ? 'Профили будут COLD_START' : 'Необязательный CSV · история поведения',
            icon: Icons.history_rounded,
            selected: _historyCsv != null && !_historyDisabled,
            onPick: _pickHistory,
            trailing: TextButton(onPressed: _disableHistory, child: const Text('Без истории', style: TextStyle(fontSize: 11))),
          );
          if (stacked) return Column(children: [first, const SizedBox(height: 10), second]);
          return Row(children: [Expanded(child: first), const SizedBox(width: 12), Expanded(child: second)]);
        }),
      ]),
    );
  }

  Widget _buildControlPanel() {
    return _panel(
      child: LayoutBuilder(builder: (context, constraints) {
        final stacked = constraints.maxWidth < 720;
        final controls = Wrap(spacing: 9, runSpacing: 9, children: [
          FilledButton.icon(
            onPressed: _isBusy || _isPlaying ? null : _startStream,
            icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.bolt_rounded, size: 18),
            label: Text(_isPaused ? 'Продолжить' : 'Запустить поток'),
          ),
          OutlinedButton.icon(
            onPressed: _isPlaying ? _pauseStream : null,
            icon: const Icon(Icons.pause_rounded, size: 18),
            label: const Text('Пауза'),
          ),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _reset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Сбросить'),
          ),
          OutlinedButton.icon(
            onPressed: _batch == null ? null : _compareWithFixture,
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Сверить с эталоном'),
          ),
        ]);
        final speed = Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.speed_rounded, size: 18, color: AppColors.muted),
          const SizedBox(width: 7),
          const Text('Интервал', style: TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(child: DropdownButton<int>(
            value: _intervalMs,
            borderRadius: BorderRadius.circular(12),
            items: const [
              DropdownMenuItem(value: 300, child: Text('0,3 сек')),
              DropdownMenuItem(value: 800, child: Text('0,8 сек')),
              DropdownMenuItem(value: 1500, child: Text('1,5 сек')),
              DropdownMenuItem(value: 2500, child: Text('2,5 сек')),
            ],
            onChanged: _isPlaying ? null : (value) => setState(() => _intervalMs = value ?? 800),
          )),
        ]);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (stacked) ...[
            controls,
            const SizedBox(height: 10),
            speed,
          ] else
            Row(children: [Expanded(child: controls), speed]),
          const SizedBox(height: 12),
          Row(children: [
            if (_isBusy) const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2)),
            if (_isBusy) const SizedBox(width: 8),
            Container(width: 7, height: 7, decoration: BoxDecoration(color: _isPlaying ? AppColors.green : AppColors.muted, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Expanded(child: Text(_status, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted))),
            if (_batch != null) Text('${_batch!.errors.length} ошибок ввода', style: TextStyle(fontSize: 10, color: _batch!.errors.isEmpty ? AppColors.green : AppColors.red)),
          ]),
        ]);
      }),
    );
  }

  Widget _buildFeedTable(List<LiveTransactionRow> rows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 38,
        dataRowMinHeight: 54,
        dataRowMaxHeight: 64,
        horizontalMargin: 12,
        columnSpacing: 22,
        headingTextStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted),
        columns: const [
          DataColumn(label: Text('ТРАНЗАКЦИЯ')),
          DataColumn(label: Text('КЛИЕНТ')),
          DataColumn(label: Text('СУММА')),
          DataColumn(label: Text('РИСК')),
          DataColumn(label: Text('РЕШЕНИЕ')),
          DataColumn(label: Text('СТАТУС')),
        ],
        rows: rows.map((row) {
          final tx = row.scored.transaction;
          return DataRow(cells: [
            DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(tx.transactionId, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 12)),
              Text(tx.timestampText, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
            ])),
            DataCell(Text(tx.clientId, style: const TextStyle(fontSize: 12, color: AppColors.ink))),
            DataCell(Text('${tx.amountText} ${tx.currency}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.ink))),
            DataCell(_ScorePill(score: row.scored.riskScore)),
            DataCell(_DecisionPill(decision: row.scored.decision)),
            DataCell(_WorkflowLabel(status: row.workflowStatus)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildReviewPage() {
    final pending = _pendingRows;
    final selected = _firstOrNull(pending.where((row) => row.scored.transaction.transactionId == _selectedReviewId));
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      final list = _panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Ожидают решения', style: Theme.of(context).textTheme.titleLarge)),
            _CountPill(count: pending.length),
          ]),
          const SizedBox(height: 12),
          if (pending.isEmpty)
            _emptyState(Icons.task_alt_rounded, 'Очередь пуста', 'Новые операции с рекомендацией REVIEW появятся здесь после скоринга.')
          else
            ...pending.map((row) => _ReviewQueueItem(
              row: row,
              selected: row.scored.transaction.transactionId == _selectedReviewId,
              onTap: () => setState(() => _selectedReviewId = row.scored.transaction.transactionId),
            )),
        ]),
      );
      final details = selected == null
          ? _panel(child: _emptyState(Icons.ads_click_rounded, 'Выберите транзакцию', 'Откройте запись слева, чтобы посмотреть факторы риска и принять решение.'))
          : _buildReviewDetails(selected);
      if (!wide) return ListView(padding: const EdgeInsets.all(20), children: [
        _pageHeading('Ручная проверка', 'Очередь подозрительных операций, ожидающих решения оператора.'),
        const SizedBox(height: 18), list, const SizedBox(height: 14), details,
      ]);
      return ListView(padding: const EdgeInsets.fromLTRB(26, 26, 26, 30), children: [
        _pageHeading('Ручная проверка', 'Очередь подозрительных операций, ожидающих решения оператора.'),
        const SizedBox(height: 22),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: list),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: details),
        ]),
      ]);
    });
  }

  Widget _buildReviewDetails(LiveTransactionRow row) {
    final tx = row.scored.transaction;
    return _panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Детали транзакции', style: Theme.of(context).textTheme.titleLarge)),
          _DecisionPill(decision: row.scored.decision),
        ]),
        const SizedBox(height: 5),
        Text(tx.transactionId, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFF6F8FC), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('РИСК-СКОР', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${row.scored.riskScore}', style: const TextStyle(fontSize: 34, height: 1, fontWeight: FontWeight.w800, color: AppColors.ink)),
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text(' / 100', style: TextStyle(fontSize: 12, color: AppColors.muted))),
            ]),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: row.scored.riskScore / 100, minHeight: 7, backgroundColor: const Color(0xFFE5EAF2), color: _riskColor(row.scored.riskScore))),
          ]),
        ),
        const SizedBox(height: 17),
        _detailLine('Клиент', tx.clientId),
        _detailLine('Сумма', '${tx.amountText} ${tx.currency}'),
        _detailLine('Время', tx.timestampText),
        _detailLine('Страна', tx.country),
        _detailLine('Категория', tx.merchantCategory),
        _detailLine('Устройство', tx.deviceId),
        _detailLine('Профиль', row.scored.profileStatus.csvValue),
        const SizedBox(height: 14),
        const Text('ФАКТОРЫ РИСКА', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.8)),
        const SizedBox(height: 9),
        if (row.scored.factors.isEmpty)
          const Text('Факторы риска не сработали.', style: TextStyle(color: AppColors.muted, fontSize: 12))
        else
          ...row.scored.factors.map((factor) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(factor.code, style: const TextStyle(fontSize: 12, color: AppColors.ink, fontWeight: FontWeight.w600))),
              Text('+${factor.points}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.red)),
            ]),
          )),
        const SizedBox(height: 14),
        if (row.isPending) ...[
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => _decide(tx.transactionId, approve: true), icon: const Icon(Icons.check_rounded, size: 17), label: const Text('Одобрить'))),
            const SizedBox(width: 9),
            Expanded(child: OutlinedButton.icon(onPressed: () => _decide(tx.transactionId, approve: false), icon: const Icon(Icons.close_rounded, size: 17), label: const Text('Отклонить'))),
          ]),
          const SizedBox(height: 8),
          const Text('Решение оператора будет сохранено отдельно от рекомендации движка.', style: TextStyle(fontSize: 10, color: AppColors.muted)),
        ] else
          _WorkflowLabel(status: row.workflowStatus),
      ]),
    );
  }

  Widget _buildReportsPage() {
    final batch = _batch;
    return ListView(padding: const EdgeInsets.fromLTRB(26, 26, 26, 32), children: [
      _pageHeading('Отчёты и аудит', 'Экспорт результатов скоринга, алертов и решений оператора.'),
      const SizedBox(height: 22),
      Wrap(spacing: 13, runSpacing: 13, children: [
        _ReportCard(title: 'Результаты скоринга', subtitle: 'Все валидные транзакции, риск-скор и рекомендация.', fileName: 'results.csv', icon: Icons.table_chart_rounded, enabled: batch != null, onExport: () => _exportReport('results')),
        _ReportCard(title: 'Алерты', subtitle: 'Только операции с рекомендацией REVIEW или BLOCK.', fileName: 'alerts.csv', icon: Icons.notifications_active_outlined, enabled: batch != null, onExport: () => _exportReport('alerts')),
        _ReportCard(title: 'Ошибки валидации', subtitle: 'Ошибочные строки, коды и причины отклонения.', fileName: 'errors.csv', icon: Icons.error_outline_rounded, enabled: batch != null, onExport: () => _exportReport('errors')),
        _ReportCard(title: 'Решения оператора', subtitle: 'Исходная рекомендация и итог ручной проверки.', fileName: 'operator-decisions.csv', icon: Icons.fact_check_outlined, enabled: batch != null, onExport: () => _exportReport('operator-decisions')),
      ]),
      const SizedBox(height: 20),
      _panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Сводка последнего запуска', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        _detailLine('Исторических операций', '${batch?.historyCount ?? 0}'),
        _detailLine('Валидных новых операций', '${batch?.scoredTransactions.length ?? 0}'),
        _detailLine('Ошибок чтения и валидации', '${batch?.errors.length ?? 0}'),
        _detailLine('Ожидают ручной проверки', '${_pendingRows.length}'),
        _detailLine('Решений оператора', '${_liveRows.where((row) => row.reviewedAt.isNotEmpty).length}'),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.verified_outlined, color: AppColors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('Сверка с эталонным results fixture доступна на вкладке мониторинга.', style: Theme.of(context).textTheme.bodySmall)),
        ]),
      ])),
    ]);
  }

  Widget _pageHeading(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 5),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ]);

  Widget _panel({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Color(0x080D2248), blurRadius: 18, offset: Offset(0, 5))],
        ),
        child: child,
      );

  Widget _emptyState(IconData icon, String title, String subtitle) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 18),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFD), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border, style: BorderStyle.solid)),
        child: Column(children: [
          Icon(icon, size: 30, color: const Color(0xFFA4B0C3)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink, fontSize: 13)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      );

  Widget _detailLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 135, child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 11, color: AppColors.ink, fontWeight: FontWeight.w600))),
        ]),
      );
}

class AppColors {
  static const blue = Color(0xFF365CF5);
  static const ink = Color(0xFF17243C);
  static const muted = Color(0xFF7C8AA1);
  static const border = Color(0xFFE8EDF5);
  static const green = Color(0xFF159568);
  static const amber = Color(0xFFCE8A1B);
  static const red = Color(0xFFD34B54);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 1.1));
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, this.count = 0});
  final IconData icon;
  final String label;
  final bool selected;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Material(
          color: selected ? const Color(0xFFEEF2FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(children: [
                Icon(icon, size: 18, color: selected ? AppColors.blue : AppColors.muted),
                const SizedBox(width: 11),
                Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, color: selected ? AppColors.blue : const Color(0xFF56647B)))),
                if (count > 0) _CountPill(count: count),
              ]),
            ),
          ),
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.width, required this.label, required this.value, required this.icon, required this.tint, required this.accent, required this.footnote});
  final double width;
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color accent;
  final String footnote;
  @override
  Widget build(BuildContext context) => Container(
        width: width < 190 ? 190 : width,
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600))),
            Container(width: 32, height: 32, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 17, color: accent)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 28, height: 1.05, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(footnote, style: const TextStyle(fontSize: 10, color: AppColors.muted)),
        ]),
      );
}

class _FileSourceCard extends StatelessWidget {
  const _FileSourceCard({required this.title, required this.fileName, required this.subtitle, required this.icon, required this.selected, required this.onPick, this.trailing});
  final String title;
  final String fileName;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onPick;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: const Color(0xFFFAFBFE), borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: AppColors.blue, size: 19)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 3),
            Text(fileName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: selected ? AppColors.green : AppColors.muted, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(fontSize: 9, color: AppColors.muted)),
          ])),
          if (trailing != null) trailing!,
          IconButton(tooltip: 'Выбрать CSV', onPressed: onPick, icon: const Icon(Icons.upload_file_rounded, color: AppColors.blue)),
        ]),
      );
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score});
  final int score;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: _riskColor(score).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(30)),
        child: Text('$score/100', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _riskColor(score))),
      );
}

class _DecisionPill extends StatelessWidget {
  const _DecisionPill({required this.decision});
  final String decision;
  @override
  Widget build(BuildContext context) {
    final color = switch (decision) {
      'APPROVE' => AppColors.green,
      'REVIEW' => AppColors.amber,
      _ => AppColors.red,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(30)),
      child: Text(decision, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.3)),
    );
  }
}

class _WorkflowLabel extends StatelessWidget {
  const _WorkflowLabel({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'AUTO_APPROVED' => ('Одобрена автоматически', AppColors.green),
      'AUTO_BLOCKED' => ('Заблокирована', AppColors.red),
      'APPROVED_BY_OPERATOR' => ('Одобрена оператором', AppColors.green),
      'REJECTED_BY_OPERATOR' => ('Отклонена оператором', AppColors.red),
      _ => ('Ожидает проверки', AppColors.amber),
    };
    return Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700));
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFFFF1D8), borderRadius: BorderRadius.circular(30)),
        child: Text('$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF9C6A15))),
      );
}

class _ReviewQueueItem extends StatelessWidget {
  const _ReviewQueueItem({required this.row, required this.selected, required this.onTap});
  final LiveTransactionRow row;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final tx = row.scored.transaction;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFF0F4FF) : const Color(0xFFFAFBFE),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(13), border: Border.all(color: selected ? const Color(0xFFB9C8FF) : AppColors.border)),
            child: Row(children: [
              Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFFFFF2DC), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.priority_high_rounded, color: AppColors.amber, size: 19)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx.transactionId, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.ink)),
                const SizedBox(height: 3),
                Text('${tx.clientId} · ${tx.amountText} ${tx.currency}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                const SizedBox(height: 4),
                Text(row.scored.riskFactorsText.replaceAll(';', ' · '), style: const TextStyle(fontSize: 9, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              _ScorePill(score: row.scored.riskScore),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.title, required this.subtitle, required this.fileName, required this.icon, required this.enabled, required this.onExport});
  final String title;
  final String subtitle;
  final String fileName;
  final IconData icon;
  final bool enabled;
  final VoidCallback onExport;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 285,
        child: Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFEAF0FF), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: AppColors.blue, size: 19)),
            const SizedBox(height: 13),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.muted, height: 1.4)),
            const SizedBox(height: 9),
            Text(fileName, style: const TextStyle(fontSize: 10, color: AppColors.blue, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: enabled ? onExport : null, icon: const Icon(Icons.download_rounded, size: 16), label: const Text('Экспорт CSV')),
          ]),
        ),
      );
}

Color _riskColor(int score) {
  if (score < 30) return AppColors.green;
  if (score < 60) return AppColors.amber;
  return AppColors.red;
}

T? _firstOrNull<T>(Iterable<T> items) {
  final iterator = items.iterator;
  return iterator.moveNext() ? iterator.current : null;
}
