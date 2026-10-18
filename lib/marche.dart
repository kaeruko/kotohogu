import 'dialogue_engine.dart';
import 'progress.dart';
import 'resident_collection.dart';

/// The opening conversation is already persisted through seenDialogues.
const tonkoMarcheOpeningDialogueId = '041_pig_middle_033';
const tonkoMarcheGreetingDialogueId = '041_pig_middle_034';
const tonkoMarcheOwner = TownResident.c041_pig_middle;

/// The first stall visit is the existing greeting; following visits tell
/// Tonko's story once each. Their read IDs survive app restarts and day changes.
const tonkoMarcheStoryDialogueIds = <String>[
  tonkoMarcheGreetingDialogueId,
  '041_pig_middle_035', // Finding courage after opening.
  '041_pig_middle_036', // First sale.
  '041_pig_middle_037', // Tasting is not buying.
  '041_pig_middle_038', // Costs and profits.
  '041_pig_middle_039', // Pricing.
  '041_pig_middle_040', // First repeat customer.
];

/// After the story, rotate everyday remarks at the counter. Keep the original
/// greeting among them, without changing its stable ID or once flag.
const tonkoMarcheDailyDialogueIds = <String>[
  '041_pig_middle_041',
  '041_pig_middle_042',
  '041_pig_middle_043',
  '041_pig_middle_044',
  '041_pig_middle_045',
  tonkoMarcheGreetingDialogueId,
];

/// Temporary debug cast membership cannot unlock the real tea stall.
bool isMarcheOpen(Progress progress) =>
    progress.residents.owned.contains(tonkoMarcheOwner) &&
    progress.seenDialogues.contains(tonkoMarcheOpeningDialogueId);

bool isMarcheStoryComplete(Progress progress) =>
    tonkoMarcheStoryDialogueIds.every(progress.seenDialogues.contains);

/// Explicit, fail-fast facility selection: never choose ordinary town chatter
/// or silently substitute another entry when the specified CMS row is invalid.
DialogueEntry selectMarcheDialogue({
  required DialogueCatalog catalog,
  required Progress progress,
  required DateTime now,
  int dailyRotation = 0,
}) {
  if (!isMarcheOpen(progress)) {
    throw StateError('Tonko marche is not open');
  }
  if (dailyRotation < 0) {
    throw RangeError.value(dailyRotation, 'dailyRotation', 'Must be >= 0');
  }
  final storyComplete = isMarcheStoryComplete(progress);
  final id = storyComplete
      ? tonkoMarcheDailyDialogueIds[
          dailyRotation % tonkoMarcheDailyDialogueIds.length]
      : tonkoMarcheStoryDialogueIds.firstWhere(
          (id) => !progress.seenDialogues.contains(id));
  final line = catalog.selectById(
    id: id,
    resident: tonkoMarcheOwner,
    progress: progress,
    now: now,
    townResidentIds: {tonkoMarcheOwner.id},
  );
  final shouldBeOnce = !storyComplete && id != tonkoMarcheGreetingDialogueId;
  if (line.once != shouldBeOnce || line.priority != -1000) {
    throw StateError('Invalid Tonko marche dialogue configuration: $id');
  }
  return line;
}
