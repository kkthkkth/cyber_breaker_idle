import 'package:flutter/material.dart';

import 'managers/dungeon_manager.dart';
import 'managers/equipment_manager.dart';
import 'managers/game_manager.dart';
import 'ui/character_screen.dart';
import 'ui/dungeon_screen.dart';
import 'ui/home_screen.dart';
import 'ui/settings_dialog.dart';
import 'ui/shop_screen.dart';
import 'ui/skill_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EquipmentManager.instance.loadEquipment();
  await GameManager.instance.loadGame();
  await DungeonManager.instance.loadDungeonData();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      GameManager.instance.saveGame();
      EquipmentManager.instance.saveEquipment();
      DungeonManager.instance.saveDungeonData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Idle RPG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 3;

  static const List<Widget> _screens = <Widget>[
    ShopScreen(),
    CharacterScreen(),
    DungeonScreen(),
    HomeScreen(),
    SkillScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B1B26),
        elevation: 0,
        leading: IconButton(
          icon: const CircleAvatar(
            backgroundColor: Color(0xFF2C2C3A),
            child: Icon(Icons.person, color: Colors.white70),
          ),
          onPressed: () => showSettingsDialog(context),
        ),
        title: const Text(
          'Cyber Breaker Idle',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          AnimatedBuilder(
            animation: GameManager.instance,
            builder: (context, _) {
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF3A3A4A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${GameManager.instance.gold}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: '샵',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '캐릭터',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.stairs),
            label: '던전',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt),
            label: '스킬',
          ),
        ],
      ),
    );
  }
}
