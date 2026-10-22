import '../data/models.dart';
import '../data/store.dart';

/// Привычки и цели из Excel-трекера «Трекер 2026» (лист «Настройки» и «Цели»).
/// У записей постоянные id, поэтому перенос на двух устройствах не создаёт дублей.
const _habits = [
  ('⏰ Подъём в 6:30', 'health', 80),
  ('😴 Сон 7–8 часов', 'health', 80),
  ('💧 Выпить 2 л воды', 'health', 90),
  ('👟 10 000 шагов', 'health', 70),
  ('🏋️ Зал / силовая', 'health', 40),
  ('🏃 Бег / кардио', 'health', 40),
  ('🧘 Зарядка / растяжка дома', 'health', 60),
  ('🍬 Без сладкого и фастфуда', 'health', 70),
  ('🥗 Белок и овощи в рационе', 'health', 80),
  ('🏫 Все пары посещены', 'study', 90),
  ('📚 Самостоятельная учёба 1 ч+', 'study', 80),
  ('🗣 Иностранный язык', 'study', 80),
  ('📝 Задания сданы вовремя', 'study', 90),
  ('🎯 Фокус-сессия без телефона', 'study', 70),
  ('✅ Главная задача дня', 'study', 80),
  ('🧠 Повторить конспекты', 'study', 60),
  ('🚗 Занятие по вождению', 'auto', 30),
  ('💻 Тесты ПДД на компьютере', 'auto', 80),
  ('📖 Теория ПДД', 'auto', 60),
  ('🧾 Записать траты', 'money', 90),
  ('🏦 Отложить деньги', 'money', 50),
  ('🛒 Без импульсивных покупок', 'money', 80),
  ('☕ Без кафе и доставки', 'money', 60),
  ('🛏 Заправить кровать', 'home', 90),
  ('🧹 Уборка 15 минут', 'home', 70),
  ('🧴 Уход за собой', 'home', 80),
  ('📵 Экранное время < 3 ч', 'home', 60),
  ('📱 Без телефона перед сном', 'home', 60),
  ('📖 Дневник / план на завтра', 'home', 70),
  ('🌳 Прогулка на воздухе', 'home', 70),
];

/// (название, сфера, что измеряем, цель, срок, откуда считать)
const _goals = [
  ('Закрыть сессию без долгов', 'study', 'сдано зачётов и экзаменов', '11', '2027-02-09', 'exams'),
  ('Получить водительские права', 'auto', 'занятий вождения', null, null, 'driving'),
  ('Накопить на цель', 'money', 'Br накоплено', '1000', '2026-12-31', 'savings'),
  ('Вес', 'health', 'кг', null, '2026-12-31', 'weight'),
  ('Часы самостоятельной учёбы', 'study', 'часов всего', '100', '2026-12-31', 'study_hours'),
  ('Иностранный язык', 'study', 'уроков / тем', null, '2026-12-31', null),
];

/// Награды из листа «Награды»: (название, условие, порог)
const _rewards = [
  ('☕ Любимый кофе', 'streak', 7),
  ('🎬 Поход в кино', 'ideal', 5),
  ('🍕 Пицца с друзьями', 'checks', 300),
  ('🎧 Новые наушники / книга', 'percent', 70),
  ('🛍 Что-то из вишлиста', 'savings', 300),
  ('💆 День отдыха без планов', 'tasks', 15),
  ('👟 Новые кроссовки', 'train', 1500),
  ('🎉 Отметить сессию', 'exams', 8),
];

/// Практики саморазвития: Джарвис каждый день даёт новое задание.
const _practices = [
  ('🗣 Скороговорки', 10, 'дикция'),
  ('🎤 Риторика', 15, 'выступления, аргументы'),
  ('💪 Уверенность', 10, 'осанка, взгляд, голос, маленькие смелые шаги'),
  ('✍️ Каллиграфия', 15, 'новый почерк'),
  ('📰 Substack', 15, 'новая информация, темы выберу позже'),
];

/// Добавить то, чего ещё нет: награды, практики, источники целей (для тех, кто перенёс раньше).
void ensureDefaults(Store store) {
  for (var i = 0; i < _rewards.length; i++) {
    final id = 'xlr${i + 1}';
    if (store.get(id) != null || store.getKv('defaults_$id') != null) continue;
    final (title, cond, threshold) = _rewards[i];
    store.create(Kinds.reward, {'title': title, 'cond': cond, 'threshold': threshold}, id: id);
    store.setKv('defaults_$id', '1');
  }
  for (var i = 0; i < _practices.length; i++) {
    final id = 'prc${i + 1}';
    if (store.get(id) != null || store.getKv('defaults_$id') != null) continue;
    final (title, minutes, about) = _practices[i];
    store.create(Kinds.practice, {'title': title, 'minutes': minutes, 'about': about, 'order': i}, id: id);
    store.setKv('defaults_$id', '1');
  }
  for (var i = 0; i < _goals.length; i++) {
    final g = store.get('xlg${i + 1}');
    if (g != null && g['source'] == null && _goals[i].$6 != null) store.patch(g.id, {'source': _goals[i].$6});
  }
}

bool excelImported(Store store) => store.get('xlh01') != null;

/// Возвращает, сколько привычек и целей добавлено.
({int habits, int goals}) importExcelTracker(Store store) {
  var h = 0, g = 0;
  for (var i = 0; i < _habits.length; i++) {
    final id = 'xlh${(i + 1).toString().padLeft(2, '0')}';
    if (store.get(id) != null) continue;
    final (title, sphere, target) = _habits[i];
    store.create(Kinds.habit, {'title': title, 'sphere': sphere, 'target': target, 'order': i}, id: id);
    h++;
  }
  for (var i = 0; i < _goals.length; i++) {
    final id = 'xlg${i + 1}';
    if (store.get(id) != null) continue;
    final (title, sphere, measure, target, due, source) = _goals[i];
    store.create(Kinds.goal, {
      'title': title,
      'sphere': sphere,
      'measure': measure,
      'target': ?target,
      'due': ?due,
      'source': ?source,
    }, id: id);
    g++;
  }
  return (habits: h, goals: g);
}
