import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'presentation/home/home_page.dart';
import 'presentation/widgets/privacy_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AppRoot()));
}

/// 应用根：MaterialApp + 启动装载
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '放心用',
      theme: buildAppTheme(),
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const BootstrapPage(),
    );
  }
}

/// 启动页：装载知识库（纯本地，无网络）+ 首次隐私确认
class BootstrapPage extends ConsumerStatefulWidget {
  const BootstrapPage({super.key});

  @override
  ConsumerState<BootstrapPage> createState() => _BootstrapPageState();
}

class _BootstrapPageState extends ConsumerState<BootstrapPage> {
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _checkPrivacy();
  }

  Future<void> _checkPrivacy() async {
    final agreed = await PrivacyDialog.hasAgreed();
    if (!mounted) return;
    if (agreed) {
      setState(() => _agreed = true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final ok = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PrivacyDialog(),
        );
        if (ok == true && mounted) {
          setState(() => _agreed = true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(packProvider);
    return async.when(
      loading: () => _loadingView(),
      error: (e, _) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 56, color: kGradeD),
                const SizedBox(height: 16),
                const Text('知识库装载失败', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 8),
                Text('$e', style: const TextStyle(color: kTextSec, fontSize: 12)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.invalidate(packProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (pack) => _agreed ? HomePage(pack: pack) : _loadingView(),
    );
  }

  Widget _loadingView() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: kPrimary),
            SizedBox(height: 24),
            Text('放心用', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('扫一扫，看懂配料表', style: TextStyle(color: kTextSec)),
            SizedBox(height: 32),
            SizedBox(width: 200, child: LinearProgressIndicator()),
            SizedBox(height: 12),
            Text('正在装载食品安全知识库…',
                style: TextStyle(color: kTextSec, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
