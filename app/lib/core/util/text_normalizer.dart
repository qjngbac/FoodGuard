import 'dart:math' as math;

/// 文本归一化工具（docs/06 §2）
class TextNormalizer {
  /// 分隔符（统一成哨兵 \u0001）
  static final RegExp _separators = RegExp(r'[、,，;；:：/|＋+&]');

  /// 百分比
  static final RegExp _percent = RegExp(r'([0-9]+\.?[0-9]*)\s*%');

  /// 全角转半角
  static String toHalfWidth(String s) {
    final buf = StringBuffer();
    for (final unit in s.codeUnits) {
      if (unit >= 0xFF01 && unit <= 0xFF5E) {
        buf.writeCharCode(unit - 0xFEE0);
      } else if (unit == 0x3000) {
        buf.write(' ');
      } else {
        buf.writeCharCode(unit);
      }
    }
    return buf.toString();
  }

  /// 提取配料表主体：去掉引导词与尾部无关段
  static String extractIngredientsBody(String raw) {
    return cleanIngredientsText(raw);
  }

  // 繁体转简体对照表（覆盖食品包装、原料配料、化学添加剂、营养成分表及通用汉字，共 824 个高频字）
  static const String _trad = '鹽醬麵麪麫麥穀雞鴨豬蝦鮮濃縮湯漿餅乾點餞醣薑蔥棗葉膠澱魚筍蔴蘇檸鈉鉀鈣鎂鐵鋅銅錳鋇鍶鋁銨氫羥醯鹼礬劑質烴熱飽纖維總膽礦營養參產標準號證級類規淨裝廠電話網絡聯銷購買獲說溫陰涼處開後請儘飲條碼過線設備著鬆調節複鹹麩變結單雙與輔專轉無純亞矽脫賽蘚異壞黃紅綠藍誘莧蘿蔔梔瓊發愛罷擺辦闆幫寶報筆畢邊錶別賓補纔財燦層冊測長嘗償場車徹陳稱懲遲齒衝蟲醜籌辭從聰叢擔導燈鄧敵糴遞東凍棟動鬥獨讀鍍對隊噸奪墮兒爾罰範販飯訪紡飛廢費紛墳奮憤風豐瘋諷鳳膚婦蓋趕個鞏貢溝構顧颳關觀館廣歸龜國華畫劃懷歡環還緩換彙會夥幾擊際濟繼績夾價駕艱監檢揀簡見鍵將槳獎講階潔屆緊錦僅進晉燼驚鯨經頸靜舊駒劇鋸鵑捲覺絕凱顆殼課墾懇庫誇塊虧擴臘蠟來賴欄攔籃爛撈勞樂釐禮裏瀝隸倆蓮連戀糧兩輛療遼獵臨鄰鈴齡靈嶺領瀏餾龍聾籠婁樓縷爐擄魯陸錄濾掄輪論羅邏鑼籮駱媽馬螞罵邁脈瞞饅蠻滿貓錨麼沒門悶們夢冪綿廟滅憫銘鳴謀畝難撓腦鬧餒內擬膩釀鳥聶齧嚀獰寧擰濘紐膿農瘧歐毆嘔謳漚盤龐拋砲賠珮轡噴鵬闢憑評鋪樸譜棲齊騎臍氣訖豈啟牽鉛遷簽謙錢鉗潛淺譴嗆槍牆薔強搶橋僑翹竅親欽寢輕傾慶窮區驅趨權顴勸卻鵲讓認韌榮絨閏潤灑薩鰓傘喪騷掃澀殺剎紗篩曬閃陝贍繕傷賞燒紹賒攝懾紳審嬸腎滲聲勝師獅濕詩屍時蝕實識駛勢適釋飾視試壽獸樞輸書贖屬術樹數誰順碩絲聳頌訟誦颼損肅歲孫鎖撻獺臺颱態攤貪癱灘壇曇譚談嘆燙濤絛討騰體題貼聽廳統頭圖塗團頹駝鴕窪襪彎灣頑萬韋違圍為衛偉偽緯葦紋聞穩問撾渦窩臥烏蕪霧誤銑戲細峽俠狹嚇廈閑賢銜憲餡鄉廂項嘯蠍協脅諧攜擷寫瀉謝銹繡虛噓須許敘緒續軒懸選癬絢學勳尋馴訓訊遜壓鴉啞訝煙嚴巖顏閻艷厭硯彥諺驗鴦陽癢樣瑤搖堯遙窯謠藥爺頁業壹醫銥頤遺儀蟻藝億憶義詣議誼譯繹蔭銀隱櫻嬰鷹應纓瑩螢熒蠅贏穎喲擁傭癰踴詠湧優憂郵鈾猶於輿餘漁娛嶼語鬱籲禦獄譽預馭鴛淵轅園員圓緣遠願約躍鑰嶽粵悅閱勻隕運蘊醞暈韻雜災載攢暫贊贓髒鑿則責擇澤賊贈紮軋閘齋債氈斬戰張漲帳賬脹趙轍這針偵診鎮陣睜爭掙徵織職執紙製緻鐘種腫週軸晝諸誅燭築磚莊壯狀濁資縱綜組鑽櫚欖蘆薈';
  static const String _simp = '盐酱面面面麦谷鸡鸭猪虾鲜浓缩汤浆饼干点饯糖姜葱枣叶胶淀鱼笋麻苏柠钠钾钙镁铁锌铜锰钡锶铝铵氢羟酰碱矾剂质烃热饱纤维总胆矿营养参产标准号证级类规净装厂电话网络联销购买获说温阴凉处开后请尽饮条码过线设备着松调节复咸麸变结单双与辅专转无纯亚硅脱赛藓异坏黄红绿蓝诱苋萝卜栀琼发爱罢摆办板帮宝报笔毕边表别宾补才财灿层册测长尝偿场车彻陈称惩迟齿冲虫丑筹辞从聪丛担导灯邓敌籴递东冻栋动斗独读镀对队吨夺堕儿尔罚范贩饭访纺飞废费纷坟奋愤风丰疯讽凤肤妇盖赶个巩贡沟构顾刮关观馆广归龟国华画划怀欢环还缓换汇会伙几击际济继绩夹价驾艰监检拣简见键将桨奖讲阶洁届紧锦仅进晋烬惊鲸经颈静旧驹剧锯鹃卷觉绝凯颗壳课垦恳库夸块亏扩腊蜡来赖栏拦篮烂捞劳乐厘礼里沥隶俩莲连恋粮两辆疗辽猎临邻铃龄灵岭领浏馏龙聋笼娄楼缕炉掳鲁陆录滤抡轮论罗逻锣箩骆妈马蚂骂迈脉瞒馒蛮满猫锚么没门闷们梦幂绵庙灭悯铭鸣谋亩难挠脑闹馁内拟腻酿鸟聂啮咛狞宁拧泞纽脓农疟欧殴呕讴沤盘庞抛炮赔佩辔喷鹏辟凭评铺朴谱栖齐骑脐气讫岂启牵铅迁签谦钱钳潜浅谴呛枪墙蔷强抢桥侨翘窍亲钦寝轻倾庆穷区驱趋权颧劝却鹊让认韧荣绒闰润洒萨鳃伞丧骚扫涩杀刹纱筛晒闪陕赡缮伤赏烧绍赊摄慑绅审婶肾渗声胜师狮湿诗尸时蚀实识驶势适释饰视试寿兽枢输书赎属术树数谁顺硕丝耸颂讼诵飕损肃岁孙锁挞獭台台态摊贪瘫滩坛昙谭谈叹烫涛绦讨腾体题贴听厅统头图涂团颓驼鸵洼袜弯湾顽万韦违围为卫伟伪纬苇纹闻稳问挝涡窝卧乌芜雾误铣戏细峡侠狭吓厦闲贤衔宪馅乡厢项啸蝎协胁谐携撷写泻谢锈绣虚嘘须许叙绪续轩悬选癣绚学勋寻驯训讯逊压鸦哑讶烟严岩颜阎艳厌砚彦谚验鸯阳痒样瑶摇尧遥窑谣药爷页业一医铱颐遗仪蚁艺亿忆义诣议谊译绎荫银隐樱婴鹰应缨莹萤荧蝇赢颖哟拥佣痈踊咏涌优忧邮铀犹于舆余渔娱屿语郁吁御狱誉预驭鸳渊辕园员圆缘远愿约跃钥岳粤悦阅匀陨运蕴酝晕韵杂灾载攒暂赞赃脏凿则责择泽贼赠扎轧闸斋债毡斩战张涨帐账胀赵辙这针侦诊镇阵睁争挣征织职执纸制致钟种肿周轴昼诸诛烛筑砖庄壮状浊资纵综组钻榈榄芦荟';

  static final Map<int, int> _t2sMap = () {
    final map = <int, int>{};
    for (var i = 0; i < _trad.length; i++) {
      map[_trad.codeUnitAt(i)] = _simp.codeUnitAt(i);
    }
    return map;
  }();

  /// 全链路繁体字转规范简体字
  static String toSimplified(String text) {
    if (text.isEmpty) return text;
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      final mapped = _t2sMap[code];
      if (mapped != null) {
        buf.writeCharCode(mapped);
      } else {
        buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }

  /// 包装曲面/微距拍摄常见 OCR 易错字与形近字纠偏字典
  static const Map<String, String> _ocrMisspellings = {
    '白砂溏': '白砂糖',
    '砂溏': '砂糖',
    '麦芽楜精': '麦芽糊精',
    '楜精': '糊精',
    '碳酸氢纳': '碳酸氢钠',
    '山梨酸纳': '山梨酸钠',
    '谷氨酸纳': '谷氨酸钠',
    '苯甲酸纳': '苯甲酸钠',
    '柠檬酸纳': '柠檬酸钠',
    '红曲红纳': '红曲红钠',
    '碳酸丐': '碳酸钙',
    '磷酸丐': '磷酸钙',
    '茶提职物': '茶提取物',
    '咖啡提职物': '咖啡提取物',
    '提职物': '提取物',
    '食朋盐': '食用盐',
    '食朋植物油': '食用植物油',
    '玉米定粉': '玉米淀粉',
    '木薯定粉': '木薯淀粉',
    '生牛轧': '生牛乳',
    '全脂乳分': '全脂乳粉',
    '脱脂乳分': '脱脂乳粉',
    '安塞蜜': '安赛蜜',
  };

  /// 针对常见包装 OCR 错别字进行纠偏
  static String correctOcrMisspellings(String text) {
    if (text.isEmpty) return text;
    var result = text;
    for (final entry in _ocrMisspellings.entries) {
      if (result.contains(entry.key)) {
        result = result.replaceAll(entry.key, entry.value);
      }
    }
    return result;
  }

  /// 深度清洗配料表文本（自动剥离“配料：”、“【配料清单】”、“保质期：12个月”等所有多余前缀与尾缀杂质，全链路繁体转简体，并自动矫正 OCR 错别字）
  static String cleanIngredientsText(String raw) {
    if (raw.trim().isEmpty) return '';
    var t = toSimplified(toHalfWidth(raw)).trim();

    // 0. OCR 常见形近字/同音字静默矫正
    t = correctOcrMisspellings(t);

    // 1. 净化前缀（支持 【配料清单】、[配料表]、配料:、配料表、原料与辅料、主要成分、主要配料等）
    t = t.replaceAll(
      RegExp(
        r'^[\s·\-*#【\[\(（]*(?:配料清单|配料表|配料|原料与辅料|原辅料|原料清单|主要配料|主要成分|成分表|成分|物料清单|原料)[】\]\)）\s]*[:：\s]?\s*',
      ),
      '',
    );
    // 处理可能残留的开头冒号、连字符或破折号
    t = t.replaceAll(RegExp(r'^[:：\s·\-—]+'), '');

    // 2. 清洗包含在括号内的内联杂质（例如 “(保质期12个月)”、“(生产日期见喷码)”）
    t = t.replaceAll(
      RegExp(r'[（\(][^）\)]*?(?:保质期|生产日期|密闭保存|常温保存|见喷码|开封后|贮存|执行标准)[^）\)]*?[）\)]'),
      '',
    );

    // 3. 截断尾部各类非配料信息（保质期、生产日期、标准、厂家、贮存、过敏提示等）
    final m = RegExp(
      r'(?:保质期|生产日期|贮存条件|贮存方法|贮藏条件|保存方法|食用方法|生产商|生产厂家|制造商|委托方|受委托方|受托方|总经销商|销售商|地址|产地|分装商|净含量|净重|规格|食品生产许可|产品标准代号|产品标准号|执行标准|企业标准|执行代号|生产批号|保质期至|此日期前最佳|温馨提示|致敏原提示|致敏物质|过敏原|本生产线|含有)(?:[:：\s\S]*)$',
    ).firstMatch(t);

    if (m != null && m.start > 0) {
      t = t.substring(0, m.start);
    }

    // 4. 清洗首尾多余标点符号与未闭合括号（如末尾句号、逗号、分号、开括号）
    t = t.replaceAll(RegExp(r'[\s,，、;；。\.·\-（\(\[【]+$'), '');
    t = t.replaceAll(RegExp(r'^[\s,，、;；。\.·\-）\)\]】]+'), '');

    return t.trim();
  }

  /// 归一化为匹配键（不用于展示）
  static String normalizeKey(String s) {
    var t = toSimplified(toHalfWidth(s));
    t = t.replaceAll(RegExp(r'[\s\u3000]'), '');
    t = t.replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), '');
    t = t.replaceAll(RegExp(r'[0-9]+\.?[0-9]*\s*%'), '');
    t = t.replaceAll(RegExp(r'含苯丙氨酸'), '');
    t = t.replaceAll(RegExp(r'(食用级|食品级|食品|食用)$'), '');
    t = t.replaceAll(RegExp(r'[、,，;；:：/|＋+&]'), '');
    return t.toLowerCase().trim();
  }

  /// 按分隔符切分（策略 A）
  static List<String> splitBySeparator(String body) {
    final unified = body.replaceAll(_separators, '\u0001');
    return unified
        .split('\u0001')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 提取百分比
  static double? extractPercent(String text) {
    final m = _percent.firstMatch(toHalfWidth(text));
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null) return null;
    return v > 100 ? null : v;
  }

  /// 是否含有分隔符（用于判断是否启用策略 B）
  static bool hasSeparator(String body) =>
      _separators.allMatches(body).length >= 2;

  /// OCR 常见错字纠偏（最小表，可扩展为 assets 中的 json）
  static const Map<String, String> ocrTypos = {
    '山犁酸': '山梨酸',
    '笨甲酸': '苯甲酸',
    '脱氢醋酸': '脱氢乙酸',
    '羧甲基纤维素纳': '羧甲基纤维素钠',
    '碳酸氢纳': '碳酸氢钠',
    '苯甲酸纳': '苯甲酸钠',
    '山梨酸甲': '山梨酸钾',
    '柠檬酸纳': '柠檬酸钠',
    '阿斯巴甜 ': '阿斯巴甜',
    '甘早': '甘草',
    '白砂溏': '白砂糖',
    '麦芽楜精': '麦芽糊精',
    '脱脂奶扮': '脱脂奶粉',
    '脱氢已酸': '脱氢乙酸',
    '安赛密': '安赛蜜',
    '赤藓精醇': '赤藓糖醇',
    '三氯蔗溏': '三氯蔗糖',
    '焦磷酸纳': '焦磷酸钠',
  };

  static String fixOcrTypos(String s) {
    var t = s;
    ocrTypos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'单[、,，]双甘油脂肪酸酯'), '单双甘油脂肪酸酯');
    return t;
  }

  /// 智能候选词推荐（基于 OCR 错别字字典与 Levenshtein 容错匹配）
  static List<String> findCorrectionCandidates(
    String word, {
    Iterable<String>? dictionary,
    int limit = 4,
  }) {
    final clean = word.trim();
    if (clean.isEmpty) return const [];

    final results = <String>{};

    // 1. 优先检查 OCR 常见错别字字典
    if (ocrTypos.containsKey(clean)) {
      results.add(ocrTypos[clean]!);
    }
    for (final entry in ocrTypos.entries) {
      if (clean.contains(entry.key)) {
        results.add(clean.replaceAll(entry.key, entry.value));
      }
    }

    // 2. 常见原料库常识兜底
    const commonIngredients = [
      '甘草', '白砂糖', '麦芽糊精', '脱脂乳粉', '全脂乳粉', '食用盐', '植物油',
      '大豆油', '棕榈油', '小麦粉', '玉米淀粉', '果葡糖浆', '鲜牛奶', '饮用水',
      '绿茶', '红茶', '乌龙茶', '咖啡豆', '可可粉', '枸杞', '决明子', '罗汉果',
      '菊花', '胖大海', '薄荷', '蜂蜜', '山梨酸钾', '苯甲酸钠', '赤藓糖醇',
      '阿斯巴甜', '三氯蔗糖', '安赛蜜', '柠檬酸', '柠檬酸钠', '维生素C',
      '磷酸氢二钠', '单双甘油脂肪酸酯', '卡拉胶', '黄原胶', '焦糖色',
    ];

    final pool = <String>{
      ...?dictionary,
      ...commonIngredients,
    };

    final candidatesWithDist = <(String, int)>[];
    for (final candidate in pool) {
      if (candidate == clean) continue;
      // 过滤长度差距过大的词
      final lenDiff = (candidate.length - clean.length).abs();
      if (lenDiff > 1) continue;

      final dist = levenshtein(clean, candidate);
      // 容错阈值：长度<=3允许距离1；长度>3允许距离<=2
      final maxDist = clean.length <= 3 ? 1 : 2;
      if (dist <= maxDist) {
        candidatesWithDist.add((candidate, dist));
      }
    }

    candidatesWithDist.sort((a, b) {
      final c = a.$2.compareTo(b.$2);
      if (c != 0) return c;
      return a.$1.length.compareTo(b.$1.length);
    });

    for (final item in candidatesWithDist) {
      results.add(item.$1);
      if (results.length >= limit) break;
    }

    return results.toList();
  }

  /// 编辑距离（用于模糊匹配 M6）
  static int levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length, n = b.length;
    var prev = List<int>.generate(n + 1, (i) => i);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(
          math.min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      prev = cur;
    }
    return prev[n];
  }
}
