# AGENTS.md

## Project overview
- This workspace is a Flutter idle RPG app with a Flame-based battle view and a bottom-navigation UI.
- Main entry point: [lib/main.dart](lib/main.dart)
- Gameplay and visuals: [lib/game/idle_game.dart](lib/game/idle_game.dart)
- State and persistence: [lib/managers/game_manager.dart](lib/managers/game_manager.dart) and [lib/managers/equipment_manager.dart](lib/managers/equipment_manager.dart)
- Screens: [lib/ui/home_screen.dart](lib/ui/home_screen.dart), [lib/ui/character_screen.dart](lib/ui/character_screen.dart), [lib/ui/shop_screen.dart](lib/ui/shop_screen.dart), and [lib/ui/skill_screen.dart](lib/ui/skill_screen.dart)

## Working conventions
- Keep gameplay state in the manager layer and let widgets react through ChangeNotifier/AnimatedBuilder rather than introducing scattered globals.
- Preserve the existing persistence pattern: load data at startup and save during app pause/inactive lifecycle in [lib/main.dart](lib/main.dart).
- Match the current Korean UI copy and dark theme styling unless a change clearly requires a different pattern.
- Prefer small, focused changes that fit the current architecture instead of rewriting the app structure.

## Typical commands
- `flutter pub get`
- `flutter test`
- `flutter analyze`
- `flutter run`

## Notes for agents
- The app uses Flame for the battle scene and shared_preferences for save/load behavior.
- If you change progression, skill, or equipment logic, keep it consistent with the existing manager-driven flow and notify listeners where appropriate.
- The home screen includes offline reward handling, so be careful when modifying lifecycle or async UI behavior.
