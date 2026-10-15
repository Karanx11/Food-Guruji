import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/dates.dart';
import '../../../core/format.dart';
import '../../../core/widgets/surfaces.dart';
import '../../../core/widgets/top_bar.dart';
import '../../log/application/log_providers.dart';
import '../../log/domain/food_entry.dart';
import '../../log/domain/nutrition.dart';
import '../../log/presentation/meal_type_ui.dart';
import '../domain/detected_food.dart';
import 'edit_food_sheet.dart';

/// Shows the foods found in a photo so the user can adjust portions, drop
/// wrong items, and log the rest to a meal. Pops `true` if anything was saved.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({
    super.key,
    this.photoBytes,
    required this.foods,
    required this.isDemo,
  });

  /// The analysed photo. Null for a barcode scan, which has no photo.
  final Uint8List? photoBytes;
  final List<DetectedFood> foods;

  /// True when the foods came from the demo analyzer, not a real model.
  final bool isDemo;

  static Route<bool> route({
    Uint8List? photoBytes,
    required List<DetectedFood> foods,
    required bool isDemo,
  }) => MaterialPageRoute<bool>(
    builder: (_) =>
        ReviewPage(photoBytes: photoBytes, foods: foods, isDemo: isDemo),
  );

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final List<DetectedFood?> _foods = List.of(widget.foods);
  late MealType _meal = MealType.forHour(ref.read(clockProvider)().hour);
  bool _saving = false;

  Iterable<DetectedFood> get _kept => _foods.whereType<DetectedFood>();

  Nutrition get _total => _kept.fold(Nutrition.zero, (sum, f) => sum + f.total);

  Future<void> _logAll() async {
    final kept = _kept.toList();
    if (kept.isEmpty) return;
    final now = ref.read(clockProvider)();
    final dayKey = dayKeyOf(now);
    final repo = ref.read(foodLogRepositoryProvider);
    final random = Random();

    setState(() => _saving = true);
    try {
      // Stagger createdAt so the entries keep the photo's order in the log.
      for (var i = 0; i < kept.length; i++) {
        final food = kept[i];
        final at = now.add(Duration(milliseconds: i));
        await repo.upsert(
          FoodEntry(
            id: FoodEntry.newId(at, random),
            dayKey: dayKey,
            meal: _meal,
            name: food.name,
            servingLabel: food.servingLabel,
            servings: food.servings,
            perServing: food.perServing,
            source: FoodSource.photo,
            createdAt: at,
          ),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Added ${kept.length} ${kept.length == 1 ? "item" : "items"} '
              'to ${_meal.label}.',
            ),
          ),
        );
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final keptCount = _kept.length;

    return Scaffold(
      appBar: appTopBar(context, title: 'Review meal'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (widget.photoBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.memory(
                widget.photoBytes!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            const _ScannedHeader(),
          const SizedBox(height: 12),
          if (widget.isDemo) ...[_DemoBanner(), const SizedBox(height: 12)],
          Text(
            '$keptCount ${keptCount == 1 ? "item" : "items"} · '
            '${_total.calories.round()} kcal',
            style: text.titleMedium,
          ),
          if (keptCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Protein ${compactNumber(_total.proteinG)} g · '
              'Carbs ${compactNumber(_total.carbsG)} g · '
              'Fat ${compactNumber(_total.fatG)} g',
              style: text.bodySmall?.copyWith(color: palette.muted),
            ),
          ],
          const SizedBox(height: 12),
          Text('Add to', style: text.titleSmall),
          const SizedBox(height: 8),
          MealChips(
            selected: _meal,
            onSelected: (m) => setState(() => _meal = m),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _foods.length; i++)
            if (_foods[i] case final food?)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _FoodCard(
                  food: food,
                  onServings: (s) =>
                      setState(() => _foods[i] = food.copyWith(servings: s)),
                  onEdit: () async {
                    final edited = await EditFoodSheet.show(context, food);
                    if (edited != null) setState(() => _foods[i] = edited);
                  },
                  onRemove: () => setState(() => _foods[i] = null),
                ),
              ),
          const SizedBox(height: 4),
          Text(
            'Estimates from a photo are approximate. Adjust anything that '
            'looks off.',
            style: text.bodySmall?.copyWith(color: palette.muted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: _saving || keptCount == 0 ? null : _logAll,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(
            keptCount == 0
                ? 'Nothing to add'
                : 'Add $keptCount to ${_meal.label}',
          ),
        ),
      ),
    );
  }
}

/// Header shown in place of a photo for a barcode scan.
class _ScannedHeader extends StatelessWidget {
  const _ScannedHeader();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 120,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Color.alphaBlend(
          AppColors.soft(primary, Theme.of(context).brightness),
          AppPalette.of(context).card,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner_rounded, size: 40, color: primary),
          const SizedBox(height: 8),
          Text('Scanned product', style: text.titleSmall),
        ],
      ),
    );
  }
}

class _DemoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final primary = Theme.of(context).colorScheme.primary;
    return AppCard(
      margin: EdgeInsets.zero,
      elevated: false,
      color: Color.alphaBlend(
        AppColors.soft(primary, Theme.of(context).brightness),
        AppPalette.of(context).card,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo results. Connect the AI backend for real photo analysis.',
              style: text.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodCard extends StatelessWidget {
  const _FoodCard({
    required this.food,
    required this.onServings,
    required this.onEdit,
    required this.onRemove,
  });

  static const double _min = 0.25;
  static const double _max = 10;
  static const double _step = 0.25;

  final DetectedFood food;
  final ValueChanged<double> onServings;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final total = food.total;
    final grams = food.gramsPerServing * food.servings;

    return AppCard(
      key: Key('review-${food.name}'),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(child: Text(food.name, style: text.titleMedium)),
                    const SizedBox(width: 8),
                    Text(
                      '${total.calories.round()} kcal',
                      style: text.titleSmall?.copyWith(
                        color: AppColors.flame,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('review-edit-${food.name}'),
                tooltip: 'Edit',
                onPressed: onEdit,
                icon: Icon(Icons.edit_outlined, color: palette.muted),
              ),
              IconButton(
                key: Key('review-remove-${food.name}'),
                tooltip: 'Remove',
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, color: palette.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _MacroPill(
                label: 'Protein',
                grams: total.proteinG,
                color: AppColors.protein,
              ),
              const SizedBox(width: 8),
              _MacroPill(
                label: 'Carbs',
                grams: total.carbsG,
                color: AppColors.carbs,
              ),
              const SizedBox(width: 8),
              _MacroPill(label: 'Fat', grams: total.fatG, color: AppColors.fat),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Sugar ${compactNumber(total.sugarG)} g   ·   '
            'Fiber ${compactNumber(total.fiberG)} g   ·   '
            'Sodium ${total.sodiumMg.round()} mg',
            style: text.bodySmall?.copyWith(color: palette.muted),
          ),
          if (food.notes case final notes?) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.eco_rounded, size: 16, color: AppColors.fat),
                const SizedBox(width: 6),
                Expanded(child: Text(notes, style: text.bodySmall)),
              ],
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              _StepButton(
                icon: Icons.remove_rounded,
                semantic: 'Less',
                onPressed: food.servings > _min
                    ? () =>
                          onServings((food.servings - _step).clamp(_min, _max))
                    : null,
              ),
              Expanded(
                child: Text(
                  '${compactNumber(food.servings, decimals: 2)} × '
                  '${food.servingLabel}   ·   ${compactNumber(grams)} g',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                semantic: 'More',
                onPressed: food.servings < _max
                    ? () =>
                          onServings((food.servings + _step).clamp(_min, _max))
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A soft pill showing one macronutrient's grams and label.
class _MacroPill extends StatelessWidget {
  const _MacroPill({
    required this.label,
    required this.grams,
    required this.color,
  });

  final String label;
  final double grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.soft(color, Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '${compactNumber(grams)} g',
              style: text.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              label,
              style: text.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.semantic,
    required this.onPressed,
  });

  final IconData icon;
  final String semantic;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: semantic,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    );
  }
}
