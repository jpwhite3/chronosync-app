import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:chronosync/data/repositories/preferences_repository.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:chronosync/logic/settings_cubit/settings_cubit.dart';
import 'package:chronosync/presentation/screens/series_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/models/user_preferences.dart';
import 'package:nested/nested.dart';

Future<void> main() async {
  await Hive.initFlutter();
  Hive.registerAdapter(SeriesAdapter());
  Hive.registerAdapter(EventAdapter());
  Hive.registerAdapter(UserPreferencesAdapter());
  await Hive.openBox<Series>('series');
  await Hive.openBox<Event>('events');
  await Hive.openBox<UserPreferences>('preferences');
  
  // Initialize default preferences if not exists
  final Box<UserPreferences> prefsBox = Hive.box<UserPreferences>('preferences');
  if (prefsBox.isEmpty) {
    await prefsBox.put('0', UserPreferences());
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider(
          create: (BuildContext context) => SeriesBloc(SeriesRepository(Hive.box('series'))),
        ),
        BlocProvider(
          create: (BuildContext context) => SettingsCubit(
            PreferencesRepository(Hive.box('preferences')),
          ),
        ),
      ],
      child: MaterialApp(
        title: 'ChronoSync',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const SeriesListScreen(),
      ),
    );
  }
}
