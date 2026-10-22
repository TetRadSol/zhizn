/// Подход из записи: «жим 60 на 10», «присед 80х5х3», «подтягивания 10», «планка 60 сек».
({String exercise, double? weight, int? reps, int sets, int? seconds})? parseWorkout(String text) {
  final l = text.toLowerCase().trim().replaceAll(',', '.');
  final name = RegExp(r'^([а-яё][а-яё\s-]*?)(?=\s*\d)').firstMatch(l)?[1]?.trim();
  if (name == null || name.isEmpty) return null;
  final ex = name[0].toUpperCase() + name.substring(1);
  var m = RegExp(r'(\d+(?:\.\d+)?)\s*(?:кг)?\s*(?:на|x|х|×|\*)\s*(\d+)(?:\s*(?:x|х|×|\*|на)\s*(\d+))?').firstMatch(l);
  if (m != null) {
    return (exercise: ex, weight: double.parse(m[1]!), reps: int.parse(m[2]!), sets: int.tryParse(m[3] ?? '') ?? 1, seconds: null);
  }
  m = RegExp(r'(\d+)\s*(сек|с|мин)').firstMatch(l);
  if (m != null) {
    final v = int.parse(m[1]!);
    return (exercise: ex, weight: null, reps: null, sets: 1, seconds: m[2] == 'мин' ? v * 60 : v);
  }
  m = RegExp(r'(\d+)(?:\s*(?:раз|повтор\w*))?(?:\s*(?:x|х|×)\s*(\d+))?').firstMatch(l);
  if (m != null) {
    return (exercise: ex, weight: null, reps: int.parse(m[1]!), sets: int.tryParse(m[2] ?? '') ?? 1, seconds: null);
  }
  return null;
}
