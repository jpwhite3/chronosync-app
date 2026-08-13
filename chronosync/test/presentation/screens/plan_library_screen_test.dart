import 'dart:typed_data';

import 'package:chronosync/data/portability/plan_archive_service.dart';
import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/repositories/plan_repository.dart';
import 'package:chronosync/domain/plan/plan.dart';
import 'package:chronosync/presentation/screens/plan_library_screen.dart';
import 'package:chronosync/presentation/theme/theme.dart';
import 'package:flutter/material.dart' hide Step;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  testWidgets('creates a sequence and opens its editor', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      plans: const <Plan>[],
    );
    await _pumpLibrary(tester, repository: repository);

    await tester.tap(find.text('Create a sequence'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Saturday conference');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(repository.createdTitles, <String>['Saturday conference']);
    expect(find.text('Edit sequence'), findsOneWidget);
    expect(find.text('Saturday conference'), findsOneWidget);
  });

  testWidgets('empty library introduces the broad sequence workflow', (
    WidgetTester tester,
  ) async {
    await _pumpLibrary(
      tester,
      repository: _LibraryRepository(plans: const <Plan>[]),
    );

    expect(find.text('Keep every clock in sync'), findsOneWidget);
    expect(
      find.text(
        'Build a sequence of timed intervals, then share the live moment '
        'with anyone nearby or online.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('event example'), findsNothing);
    expect(find.textContaining('plan', findRichText: true), findsNothing);
  });

  testWidgets('repository failures do not expose internal details', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      plans: <Plan>[_plan()],
      duplicateError: StateError('db=/private/plans.sqlite secret=ROOM_KEY'),
    );
    await _pumpLibrary(tester, repository: repository);

    await tester.tap(find.byTooltip('Sequence actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not duplicate the sequence. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('plans.sqlite'), findsNothing);
    expect(find.textContaining('ROOM_KEY'), findsNothing);
  });

  testWidgets('example creation failures recover with safe guidance', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      createError: StateError('disk path=/private/example.sqlite'),
    );
    await _pumpLibrary(tester, repository: repository);

    await tester.tap(find.text('Try a sample sequence'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not create the sample sequence. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('example.sqlite'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed example population removes its empty draft', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      saveError: StateError('step transaction failed'),
    );
    await _pumpLibrary(tester, repository: repository);

    await tester.tap(find.text('Try a sample sequence'));
    await tester.pumpAndSettle();

    expect(repository.plans, isEmpty);
    expect(repository.deletedIds, <String>['plan-1']);
    expect(
      find.text('Could not create the sample sequence. Try again.'),
      findsOneWidget,
    );
  });

  testWidgets('delete failures keep the plan and show safe guidance', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      plans: <Plan>[_plan()],
      deleteError: StateError('sqlite code=19 user=/private/name'),
    );
    await _pumpLibrary(tester, repository: repository);

    await tester.tap(find.byTooltip('Sequence actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not delete the sequence. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('sqlite code'), findsNothing);
    expect(find.text('Opening night'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('library load failures use safe recovery guidance', (
    WidgetTester tester,
  ) async {
    final _LibraryRepository repository = _LibraryRepository(
      watchError: StateError('database /private/user/chronosync.sqlite'),
    );
    await _pumpLibrary(tester, repository: repository);

    expect(
      find.text('ChronoSync could not open your sequences.'),
      findsOneWidget,
    );
    expect(find.textContaining('chronosync.sqlite'), findsNothing);
  });

  testWidgets('sequence cards remain overflow-free at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(
      tester,
      repository: _LibraryRepository(plans: <Plan>[_plan()]),
      textScale: 2,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pumpAndSettle();

    expect(find.text('Opening night'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact library has one aligned New sequence action', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpLibrary(
      tester,
      repository: _LibraryRepository(plans: <Plan>[_plan()]),
    );

    expect(find.text('New sequence'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.getTopLeft(find.text('Your sequences')).dx, lessThan(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan card surface is not a nested interactive control', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _pumpLibrary(
      tester,
      repository: _LibraryRepository(plans: <Plan>[_plan()]),
    );

    final SemanticsNode card = tester.getSemantics(
      find.bySemanticsLabel('Opening night, 1 interval'),
    );
    expect(card.flagsCollection.isButton, isFalse);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('singular import copy names one sequence and one interval', (
    WidgetTester tester,
  ) async {
    final Uint8List archive = const PlanArchiveService().exportPlans(<Plan>[
      _plan(),
    ]);
    await _pumpLibrary(
      tester,
      repository: _LibraryRepository(plans: const <Plan>[]),
      fileService: PortabilityFileService(filePicker: _ArchivePicker(archive)),
    );

    await tester.tap(find.byTooltip('Sequence library actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import .chronosync'));
    await tester.pumpAndSettle();

    expect(
      find.text('1 sequence and 1 interval were exported by ChronoSync 1.0.0.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    expect(find.text('Imported 1 sequence'), findsOneWidget);
  });
}

Future<void> _pumpLibrary(
  WidgetTester tester, {
  required PlanRepository repository,
  double textScale = 1,
  PortabilityFileService fileService = const PortabilityFileService(),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ChronoTheme.light(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: PlanLibraryScreen(
        repository: repository,
        archiveService: const PlanArchiveService(),
        fileService: fileService,
        onStartPlan: (Plan _) async {},
        onJoinSession: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final class _ArchivePicker implements FilePickerAdapter {
  const _ArchivePicker(this.bytes);

  final Uint8List bytes;

  @override
  Future<FilePickerResult?> pickFiles({
    required String dialogTitle,
    required FileType type,
    required List<String> allowedExtensions,
    required bool allowMultiple,
    required bool withData,
    required bool withReadStream,
  }) async {
    return FilePickerResult(<PlatformFile>[
      PlatformFile(
        name: 'one-sequence.chronosync',
        size: bytes.length,
        readStream: Stream<List<int>>.value(bytes),
      ),
    ]);
  }

  @override
  Future<String?> saveFile({
    required String dialogTitle,
    required String fileName,
    required FileType type,
    required List<String> allowedExtensions,
    required Uint8List bytes,
  }) async => null;
}

Plan _plan({String title = 'Opening night'}) {
  final DateTime timestamp = DateTime.utc(2026, 1, 1);
  return Plan(
    id: 'plan-1',
    title: title,
    defaultCueProfile: CueProfile(),
    steps: <Step>[
      Step(
        id: 'step-1',
        planId: 'plan-1',
        position: 0,
        title: 'Doors open',
        durationSeconds: 300,
      ),
    ],
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

final class _LibraryRepository implements PlanRepository {
  _LibraryRepository({
    List<Plan> plans = const <Plan>[],
    this.watchError,
    this.duplicateError,
    this.createError,
    this.saveError,
    this.deleteError,
  }) : plans = List<Plan>.of(plans);

  final List<Plan> plans;
  final Object? watchError;
  final Object? duplicateError;
  final Object? createError;
  final Object? saveError;
  final Object? deleteError;
  final List<String> createdTitles = <String>[];
  final List<String> deletedIds = <String>[];

  @override
  Future<Plan> createPlan({required String title}) async {
    if (createError case final Object error) {
      throw error;
    }
    createdTitles.add(title);
    final Plan plan = _plan(title: title).copyWith(steps: const <Step>[]);
    plans.add(plan);
    return plan;
  }

  @override
  Future<void> deletePlan(String id) async {
    if (deleteError case final Object error) {
      throw error;
    }
    deletedIds.add(id);
    plans.removeWhere((Plan plan) => plan.id == id);
  }

  @override
  Future<Plan> duplicatePlan(String id) async {
    if (duplicateError case final Object error) {
      throw error;
    }
    return _plan(title: 'Opening night copy');
  }

  @override
  Future<List<Plan>> getAllPlans() async => plans;

  @override
  Future<Plan?> getPlan(String id) async => plans.firstOrNull;

  @override
  Future<void> savePlan(Plan plan) async {
    if (saveError case final Object error) {
      throw error;
    }
    final int index = plans.indexWhere((Plan value) => value.id == plan.id);
    if (index < 0) {
      plans.add(plan);
    } else {
      plans[index] = plan;
    }
  }

  @override
  Future<void> savePlans(Iterable<Plan> plans) async {}

  @override
  Stream<List<Plan>> watchPlans() {
    if (watchError case final Object error) {
      return Stream<List<Plan>>.error(error);
    }
    return Stream<List<Plan>>.value(plans);
  }
}
