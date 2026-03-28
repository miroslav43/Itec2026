import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state_provider.dart';
import 'providers/socket_provider.dart';
import 'providers/drawing_provider.dart';
import 'screens/loading_screen.dart';
import 'services/image_matching_service.dart';
import 'services/player_stats_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ImageMatchingService.initialize();
  await PlayerStatsService.load();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ITecOverrideApp());
}

class ITecOverrideApp extends StatelessWidget {
  const ITecOverrideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => SocketProvider()),
        ChangeNotifierProvider(create: (_) => DrawingProvider()),
      ],
      child: MaterialApp(
        title: 'iTEC OVERRIDE',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const LoadingScreen(),
      ),
    );
  }
}

