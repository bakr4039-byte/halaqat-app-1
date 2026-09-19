import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemSound, SystemSoundType;
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/json_utils.dart';

/// عجلة الحظ التحفيزية:
/// - إدخال أسماء الطلاب يدويًا (واحد واحد أو لصق قائمة دفعة واحدة)، أو
///   استيرادها من قائمة الطلاب الفعلية، في قائمة ديناميكية قابلة للحذف —
///   تُحفظ مؤقتًا في الذاكرة فقط (مصفوفة عادية) ومفيش أي حفظ في Firestore.
/// - عجلة دائرية تنقسم تلقائيًا بعدد الأسماء، مؤشر ثابت أعلاها، ودوران
///   عشوائي (الفائز بيتحدد قبل بدء الحركة) يتسارع ثم يتباطأ تدريجيًا لحد ما
///   يستقر، مع اهتزاز/صوت نظام أثناء الدوران وكونفيتي عند التوقف.
/// - خيار استبعاد الفائز تلقائيًا من الجولة الجاية، ووضع عرض بشاشة كاملة
///   لعرض العجلة أمام الطلاب.
class LuckyWheelTab extends StatefulWidget {
  final String circleId;
  final String? filterTeacherId;
  const LuckyWheelTab({super.key, required this.circleId, this.filterTeacherId});

  @override
  State<LuckyWheelTab> createState() => _LuckyWheelTabState();
}

class _LuckyWheelTabState extends State<LuckyWheelTab> {
  final List<String> _names = [];
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  bool _importing = false;
  bool _autoRemoveWinner = false;
  bool _spinning = false; // بتتحدّث من _WheelDisplay عشان نعطّل باقي الأزرار أثناء الدوران

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _addName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _names.add(name));
    _nameController.clear();
    _nameFocusNode.requestFocus();
  }

  void _removeName(int index) => setState(() => _names.removeAt(index));

  Future<void> _pasteBulkNames() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('لصق قائمة أسماء'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 8,
            minLines: 4,
            autofocus: true,
            textDirection: TextDirection.rtl,
            decoration: const InputDecoration(
              hintText: 'اكتب أو الصق اسمًا في كل سطر...',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;

    final newNames = result.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (newNames.isEmpty) return;

    var added = 0;
    setState(() {
      for (final n in newNames) {
        if (!_names.contains(n)) {
          _names.add(n);
          added++;
        }
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added == 0 ? 'كل الأسماء دي موجودة بالفعل.' : 'تمت إضافة $added اسمًا.')),
    );
  }

  Future<void> _importFromStudents() async {
    setState(() => _importing = true);
    try {
      final api = context.read<ApiService>();
      final results = await Future.wait([
        api.getStudents(widget.circleId),
        api.getInitialData(widget.circleId),
      ]);
      var students = asMapList(results[0]['students']);
      if (widget.filterTeacherId != null) {
        final teachers = asMapList(results[1]['teachers']);
        students = students.where((s) => studentBelongsToTeacher(s, widget.filterTeacherId, teachers)).toList();
      }
      if (!mounted) return;
      var added = 0;
      setState(() {
        for (final s in students) {
          final name = (s['name'] ?? '').toString().trim();
          if (name.isNotEmpty && !_names.contains(name)) {
            _names.add(name);
            added++;
          }
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(added == 0 ? 'لا يوجد طلاب جدد لاستيرادهم.' : 'تم استيراد $added اسمًا.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _WheelFullscreenPage(names: _names, autoRemoveWinner: _autoRemoveWinner),
    ));
    // بعد الرجوع من ملء الشاشة، ممكن يكون الفائز اتشال تلقائيًا من نفس
    // القائمة (نفس الـ List بالمرجع) — لازم نعمل رسم من جديد عشان الشرائح
    // تنعكس صح فوق.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = !_spinning;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    focusNode: _nameFocusNode,
                    enabled: controlsEnabled,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطالب',
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addName(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: controlsEnabled ? _addName : null,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text('القائمة (${_names.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: controlsEnabled ? _pasteBulkNames : null,
                  icon: const Icon(Icons.content_paste_outlined, size: 18),
                  label: const Text('لصق قائمة'),
                ),
                TextButton.icon(
                  onPressed: controlsEnabled && !_importing ? _importFromStudents : null,
                  icon: _importing
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.groups_outlined, size: 18),
                  label: const Text('استيراد من الطلاب'),
                ),
                if (_names.isNotEmpty)
                  TextButton.icon(
                    onPressed: controlsEnabled
                        ? () => setState(() => _names.clear())
                        : null,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.danger),
                    label: const Text('مسح الكل', style: TextStyle(color: AppColors.danger)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Switch(
                  value: _autoRemoveWinner,
                  onChanged: controlsEnabled ? (v) => setState(() => _autoRemoveWinner = v) : null,
                  activeThumbColor: AppColors.primary,
                ),
                const Expanded(
                  child: Text('استبعاد الفائز تلقائيًا من الجولة الجاية', style: TextStyle(fontSize: 13)),
                ),
                IconButton(
                  onPressed: _names.length < 2 ? null : _openFullscreen,
                  icon: const Icon(Icons.fullscreen),
                  tooltip: 'عرض بشاشة كاملة',
                ),
              ],
            ),
          ),
          SizedBox(
            height: 76,
            child: _names.isEmpty
                ? const Center(
                    child: Text('أضف أسماء الطلاب عشان تبدأ العجلة', style: TextStyle(color: Colors.grey)))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _names.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final color = wheelSliceColor(i, _names.length);
                      return Chip(
                        label: Text(_names[i]),
                        backgroundColor: color.withValues(alpha: 0.15),
                        side: BorderSide(color: color),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: controlsEnabled ? () => _removeName(i) : null,
                      );
                    },
                  ),
          ),
          const Divider(height: 16),
          Expanded(
            child: _WheelDisplay(
              names: _names,
              autoRemoveWinner: _autoRemoveWinner,
              onNamesChanged: () => setState(() {}),
              onSpinningChanged: (v) => setState(() => _spinning = v),
            ),
          ),
        ],
      ),
    );
  }
}

/// صفحة عرض العجلة بشاشة كاملة — نفس القائمة (بنفس الـ List reference) بس
/// بدون أدوات إدارة الأسماء، مناسبة لعرضها أمام الطلاب على بروجكتور/شاشة.
class _WheelFullscreenPage extends StatelessWidget {
  final List<String> names;
  final bool autoRemoveWinner;
  const _WheelFullscreenPage({required this.names, required this.autoRemoveWinner});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 48),
              child: _WheelDisplay(names: names, autoRemoveWinner: autoRemoveWinner, large: true),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                tooltip: 'إغلاق',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// العجلة نفسها + زر "ابدأ" + منطق الدوران العشوائي والاهتزاز/الصوت
/// والكونفيتي — مكوّن مستقل يُستخدم في التاب العادي وفي وضع ملء الشاشة معًا.
class _WheelDisplay extends StatefulWidget {
  final List<String> names;
  final bool autoRemoveWinner;
  final VoidCallback? onNamesChanged;
  final ValueChanged<bool>? onSpinningChanged;
  final bool large;
  const _WheelDisplay({
    required this.names,
    required this.autoRemoveWinner,
    this.onNamesChanged,
    this.onSpinningChanged,
    this.large = false,
  });

  @override
  State<_WheelDisplay> createState() => _WheelDisplayState();
}

class _WheelDisplayState extends State<_WheelDisplay> with SingleTickerProviderStateMixin {
  late final AnimationController _spinController;
  late final ConfettiController _confettiController;
  Animation<double> _spinAnimation = const AlwaysStoppedAnimation<double>(0.0);
  double _currentAngle = 0; // آخر زاوية استقرت عندها العجلة، عشان الدورة الجاية تكمل منها
  int? _winnerIndex;
  bool _spinning = false;
  int _lastTickSlice = 0;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
      ..addListener(_onControllerTick);
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    _spinController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  /// اهتزاز خفيف (haptic) كل ما العجلة تعدّي على حد شريحة أثناء الدوران —
  /// إحساس "تكة تكة" بدون الحاجة لملف صوت مخصص.
  void _onControllerTick() {
    if (!_spinning || widget.names.isEmpty) return;
    final sliceAngle = 2 * pi / widget.names.length;
    final slice = (_spinAnimation.value / sliceAngle).floor();
    if (slice != _lastTickSlice) {
      _lastTickSlice = slice;
      HapticFeedback.selectionClick();
    }
  }

  void _spin() {
    final names = widget.names;
    if (_spinning || names.length < 2) return;

    final winnerIndex = _random.nextInt(names.length);
    final sliceAngle = 2 * pi / names.length;
    final sliceCenter = (winnerIndex + 0.5) * sliceAngle;
    final extraTurns = 6 + _random.nextInt(3); // 6 إلى 8 لفات كاملة زيادة للإحساس بالحركة

    // الزاوية المطلوبة عشان مركز شريحة الفائز يستقر بالظبط تحت المؤشر الثابت
    // أعلى العجلة، مع الاستمرار في نفس اتجاه الدوران من آخر زاوية توقفنا عندها.
    final requiredDelta = (-sliceCenter - _currentAngle) % (2 * pi);
    final targetAngle = _currentAngle + extraTurns * 2 * pi + requiredDelta;
    _lastTickSlice = (_currentAngle / sliceAngle).floor();

    setState(() {
      _spinning = true;
      _winnerIndex = null;
      // تسارع قصير في البداية ثم تباطؤ تدريجي طويل لحد التوقف الكامل —
      // منحنى الجيب (sine) بيدي سرعة صفر في البداية والنهاية وأعلى سرعة في المنتصف.
      _spinAnimation = Tween<double>(begin: _currentAngle, end: targetAngle).animate(
        CurvedAnimation(parent: _spinController, curve: Curves.easeInOutSine),
      );
    });
    widget.onSpinningChanged?.call(true);

    _spinController
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        _currentAngle = targetAngle % (2 * pi);
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
        _confettiController.play();
        setState(() {
          _spinning = false;
          _winnerIndex = winnerIndex;
          _spinAnimation = AlwaysStoppedAnimation<double>(_currentAngle);
        });
        widget.onSpinningChanged?.call(false);
        _showWinnerDialog(winnerIndex);
      });
  }

  Future<void> _showWinnerDialog(int winnerIndex) async {
    if (!mounted || winnerIndex >= widget.names.length) return;
    final name = widget.names[winnerIndex];

    var autoRemoved = false;
    if (widget.autoRemoveWinner) {
      final idx = widget.names.indexOf(name);
      if (idx != -1) {
        setState(() {
          widget.names.removeAt(idx);
          _winnerIndex = null;
        });
        widget.onNamesChanged?.call();
        autoRemoved = true;
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🎉 مبروك!'),
        content: Text(
          autoRemoved ? 'الفائز هو: $name\n(اتشال من القائمة تلقائيًا لجولة جاية عادلة)' : 'الفائز هو: $name',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!autoRemoved)
            TextButton(
              onPressed: () {
                final idx = widget.names.indexOf(name);
                if (idx != -1) {
                  setState(() {
                    widget.names.removeAt(idx);
                    _winnerIndex = null;
                  });
                  widget.onNamesChanged?.call();
                }
                Navigator.pop(context);
              },
              child: const Text('إزالة من القائمة'),
            ),
          ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.names;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = min(constraints.maxWidth, constraints.maxHeight - 40) *
                    (widget.large ? 0.95 : 0.9);
                final safeSize = size.isFinite && size > 0 ? size : 200.0;
                return SizedBox(
                  width: safeSize,
                  height: safeSize + 34,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 34,
                        child: AnimatedBuilder(
                          animation: _spinAnimation,
                          builder: (context, child) =>
                              Transform.rotate(angle: _spinAnimation.value, child: child),
                          child: CustomPaint(
                            size: Size(safeSize, safeSize),
                            painter: _WheelPainter(names: names, highlightIndex: _winnerIndex),
                          ),
                        ),
                      ),
                      const Positioned(
                        top: 0,
                        child: Icon(Icons.arrow_drop_down, size: 46, color: AppColors.primaryDark),
                      ),
                      IgnorePointer(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConfettiWidget(
                            confettiController: _confettiController,
                            blastDirectionality: BlastDirectionality.explosive,
                            shouldLoop: false,
                            numberOfParticles: 24,
                            maxBlastForce: 18,
                            minBlastForce: 8,
                            gravity: 0.25,
                            colors: List.generate(6, (i) => wheelSliceColor(i, 6)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, widget.large ? 24 : 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (names.length < 2 || _spinning) ? null : _spin,
              icon: _spinning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.casino),
              label: Text(
                _spinning ? 'جاري الدوران...' : (names.length < 2 ? 'أضف طالبين على الأقل' : 'ابدأ'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: EdgeInsets.symmetric(vertical: widget.large ? 20 : 16),
                textStyle: TextStyle(fontSize: widget.large ? 20 : 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// لون ثابت ومتناسق لكل شريحة حسب ترتيبها — بيتوزع على دائرة الألوان (Hue)
/// عشان كل الشرائح تبقى واضحة ومختلفة عن بعض حتى مع عدد كبير من الطلاب.
Color wheelSliceColor(int index, int total) {
  final hue = (index * 360 / max(total, 1)) % 360;
  return HSLColor.fromAHSL(1, hue, 0.55, 0.55).toColor();
}

Color _textColorOn(Color background) => background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;

class _WheelPainter extends CustomPainter {
  final List<String> names;
  final int? highlightIndex;
  _WheelPainter({required this.names, this.highlightIndex});

  static const double _startOffset = -pi / 2; // البداية من أعلى العجلة (12 الساعة)

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (names.isEmpty) {
      canvas.drawCircle(center, radius, Paint()..color = Colors.grey.shade300);
      _drawCenteredText(canvas, center, 'أضف أسماء\nللبدء', radius * 1.2, Colors.grey.shade600);
      return;
    }

    final sliceAngle = 2 * pi / names.length;

    for (var i = 0; i < names.length; i++) {
      final color = wheelSliceColor(i, names.length);
      final startAngle = _startOffset + i * sliceAngle;

      canvas.drawArc(rect, startAngle, sliceAngle, true, Paint()..color = color);
      canvas.drawArc(
        rect,
        startAngle,
        sliceAngle,
        true,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      final midAngle = startAngle + sliceAngle / 2;
      final maxLabelWidth = radius * (names.length > 14 ? 0.5 : 0.8);
      canvas.save();
      canvas.translate(
        center.dx + cos(midAngle) * radius * 0.65,
        center.dy + sin(midAngle) * radius * 0.65,
      );
      canvas.rotate(midAngle + pi / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: names[i],
          style: TextStyle(
            color: _textColorOn(color),
            fontSize: names.length > 10 ? 10 : 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.rtl,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: maxLabelWidth);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    if (highlightIndex != null && highlightIndex! < names.length) {
      final hStart = _startOffset + highlightIndex! * sliceAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        hStart,
        sliceAngle,
        true,
        Paint()
          ..color = Colors.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
    }

    canvas.drawCircle(
      center,
      radius - 2,
      Paint()
        ..color = AppColors.primaryDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(center, radius * 0.07, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius * 0.07,
      Paint()
        ..color = AppColors.primaryDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawCenteredText(Canvas canvas, Offset center, String text, double maxWidth, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) {
    return highlightIndex != oldDelegate.highlightIndex || !listEquals(names, oldDelegate.names);
  }
}
