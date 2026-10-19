/// 关注人群
enum Population {
  adult('ADULT', '成人'),
  pregnancy('PREGNANCY', '孕产妇'),
  child('CHILD', '儿童'),
  elder('ELDER', '老人');

  const Population(this.code, this.label);
  final String code;
  final String label;

  static Population fromCode(String? code) =>
      values.firstWhere((e) => e.code == code, orElse: () => adult);
}

/// 慢病
enum Chronic {
  hypertension('HYPERTENSION', '高血压'),
  diabetes('DIABETES', '糖尿病'),
  kidney('KIDNEY', '肾病'),
  gout('GOUT', '痛风');

  const Chronic(this.code, this.label);
  final String code;
  final String label;

  static Chronic? fromCode(String code) {
    for (final e in values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

/// 用户画像：人群 + 慢病 + 过敏原订阅
class UserProfile {
  const UserProfile({
    this.population = Population.adult,
    this.chronics = const [],
    this.allergens = const [],
  });

  final Population population;
  final List<Chronic> chronics;
  final List<String> allergens;

  /// 参与评分的人群代码集合（人群 + 慢病）
  List<String> get populationCodes =>
      [population.code, ...chronics.map((e) => e.code)];

  bool get isDefault =>
      population == Population.adult && chronics.isEmpty && allergens.isEmpty;

  UserProfile copyWith({
    Population? population,
    List<Chronic>? chronics,
    List<String>? allergens,
  }) =>
      UserProfile(
        population: population ?? this.population,
        chronics: chronics ?? this.chronics,
        allergens: allergens ?? this.allergens,
      );
}

/// 过敏原订阅项（用于设置页 UI）
class AllergenOption {
  const AllergenOption({required this.code, required this.nameZh});

  final String code;
  final String nameZh;
}
