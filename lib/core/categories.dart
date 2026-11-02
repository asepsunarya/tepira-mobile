/// Expense categories, the same nine as the web (`tepira: lib/categories.ts`,
/// SPEC-v2 §2). The mobile API sends and accepts the [ExpenseCategory.label];
/// an expense without a category has `category: null`.
library;

class ExpenseCategory {
  const ExpenseCategory({
    required this.key,
    required this.label,
    required this.group,
  });

  /// The web's stored key; the mobile API never uses it.
  final String key;

  /// Sent and received by the mobile API, and shown to the user.
  final String label;

  /// Heading the category is listed under.
  final String group;
}

/// In web order, grouped by [ExpenseCategory.group].
const List<ExpenseCategory> kExpenseCategories = [
  ExpenseCategory(
    key: 'makan_harian',
    label: 'Makan harian',
    group: 'Kebutuhan wajib',
  ),
  ExpenseCategory(
    key: 'transport',
    label: 'Transport',
    group: 'Kebutuhan wajib',
  ),
  ExpenseCategory(
    key: 'pulsa_internet',
    label: 'Pulsa & Internet',
    group: 'Kebutuhan wajib',
  ),
  ExpenseCategory(
    key: 'listrik_kos',
    label: 'Listrik / Air / Kos',
    group: 'Kebutuhan wajib',
  ),
  ExpenseCategory(
    key: 'langganan',
    label: 'Langganan (Spotify, Netflix, dll)',
    group: 'Kewajiban & rutin',
  ),
  ExpenseCategory(
    key: 'kesehatan',
    label: 'Kesehatan / Obat',
    group: 'Kewajiban & rutin',
  ),
  ExpenseCategory(
    key: 'sosial',
    label: 'Sosial (sedekah / bantu keluarga)',
    group: 'Kewajiban & rutin',
  ),
  ExpenseCategory(
    key: 'nongkrong',
    label: 'Nongkrong / jajan',
    group: 'Hiburan & fleksibel',
  ),
  ExpenseCategory(
    key: 'belanja_kecil',
    label: 'Belanja kecil',
    group: 'Hiburan & fleksibel',
  ),
];

/// The category whose label is [label], or null for no category or a label
/// the app does not know (e.g. one stored by an older client).
ExpenseCategory? categoryByLabel(String? label) {
  for (final category in kExpenseCategories) {
    if (category.label == label) return category;
  }
  return null;
}

/// [kExpenseCategories] grouped by [ExpenseCategory.group], groups and
/// categories in list order.
Map<String, List<ExpenseCategory>> categoriesByGroup() {
  final groups = <String, List<ExpenseCategory>>{};
  for (final category in kExpenseCategories) {
    (groups[category.group] ??= []).add(category);
  }
  return groups;
}
