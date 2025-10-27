import 'package:bloc_test/bloc_test.dart';
import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:chronosync/logic/series_bloc/series_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'series_bloc_test.mocks.dart';

@GenerateMocks(<Type>[SeriesRepository, Box])
void main() {
  group('SeriesBloc', () {
    late SeriesBloc seriesBloc;
    late MockSeriesRepository mockRepository;
    late MockBox<Event> mockEventBox;

    setUp(() {
      mockRepository = MockSeriesRepository();
      mockEventBox = MockBox<Event>();
      seriesBloc = SeriesBloc(mockRepository);
      
      // Stub the name property for mockEventBox
      when(mockEventBox.name).thenReturn('events');
    });

    tearDown(() {
      seriesBloc.close();
    });

    test('initial state is SeriesInitial', () {
      expect(seriesBloc.state, equals(SeriesInitial()));
    });

    blocTest<SeriesBloc, SeriesState>(
      'emits [SeriesLoaded] when LoadSeries is added',
      build: () {
        final List<Series> seriesList = <Series>[
          Series(title: 'Test Series 1', events: HiveList(mockEventBox)),
          Series(title: 'Test Series 2', events: HiveList(mockEventBox)),
        ];
        when(mockRepository.getAllSeries()).thenReturn(seriesList);
        return seriesBloc;
      },
      act: (SeriesBloc bloc) => bloc.add(LoadSeries()),
      expect: () => <Matcher>[
        isA<SeriesLoaded>()
            .having((SeriesLoaded s) => s.series.length, 'series length', 2)
            .having((SeriesLoaded s) => s.series[0].title, 'first series title', 'Test Series 1')
            .having((SeriesLoaded s) => s.series[1].title, 'second series title', 'Test Series 2'),
      ],
    );

    blocTest<SeriesBloc, SeriesState>(
      'emits [SeriesLoaded] when AddSeries is added',
      build: () {
        when(mockRepository.addSeries(any)).thenAnswer((_) async {});
        when(mockRepository.getAllSeries()).thenReturn(<Series>[]);
        return seriesBloc;
      },
      act: (SeriesBloc bloc) => bloc.add(
        AddSeries(Series(title: 'New Series', events: HiveList(mockEventBox))),
      ),
      expect: () => <Matcher>[
        isA<SeriesLoaded>()
            .having((SeriesLoaded s) => s.series.length, 'series length', 0),
      ],
    );
  });
}
