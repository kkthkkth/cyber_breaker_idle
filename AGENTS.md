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



## AI Agent Office & Automation Rules

### 1. Image Processing & Asset Pipeline
- When a raw asset is added or image background removal is requested, run `python process_image.py <input_path> <output_path>`.
- Place generated images in the `assets/` directory and update `pubspec.yaml` assets configuration if needed.

### 2. QA & Test Automation Workflow
- After modifying or adding features, always run `flutter analyze` and `flutter test`.
- If tests fail or static analysis throws errors, analyze the output, fix the code automatically, and re-run tests until all checks pass.
- Maintain existing state architecture (Managers + ChangeNotifier) during all auto-refactoring.

### 3. Role Delegation Protocol
- **Planning/PM**: Update or review project specs, feature flows, and tasks before implementation.
- **Developer**: Implement clean Dart/Flame code adhering to existing project architecture.
- **QA/Tester**: Verify widget/game logic with tests and ensure zero analysis errors.