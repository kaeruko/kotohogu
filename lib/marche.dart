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

/// Later chapters about Tonko's part-time work and her dream of a shop.
/// Their cumulative kotohogi requirements live in the editable CMS dialogue
/// entries (type: kotohogi). Unmet milestones never block everyday chatter.
const tonkoMarcheMilestoneDialogueIds = <String>[
  '041_pig_middle_050', // Supermarket work and two monthly market dates.
  '041_pig_middle_051', // Wages become herb seedlings.
  '041_pig_middle_052', // Sales are not profit.
  '041_pig_middle_053', // Customers returning to the small market.
  '041_pig_middle_054', // Keep part-time work while planning a shop.
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
  // The opening and first-customer chapters retain their original order.
  // Later, each earned-kotohogi milestone is read once, in sequence.
  // A milestone that is not ready leaves ordinary market chatter available.
  if (storyComplete) {
    for (final milestoneId in tonkoMarcheMilestoneDialogueIds) {
      if (progress.seenDialogues.contains(milestoneId)) {
        continue;
      }
      final milestone = catalog.entries.singleWhere(
          (entry) => entry.id == milestoneId);
      if (!milestone.matches(progress, now, {tonkoMarcheOwner.id})) {
        break;
      }
      if (!milestone.once || milestone.priority != -1000) {
        throw StateError('Invalid Tonko milestone dialogue: $milestoneId');
      }
      return catalog.selectById(
        id: milestoneId,
        resident: tonkoMarcheOwner,
        progress: progress,
        now: now,
        townResidentIds: {tonkoMarcheOwner.id},
      );
    }
  }
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
