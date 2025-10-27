import 'package:chronosync/data/models/event.dart';
import 'package:chronosync/data/models/series.dart';
import 'package:chronosync/data/repositories/series_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'series_repository_test.mocks.dart';

@GenerateMocks(<Type>[Box])

void main() {
  group('SeriesRepository', () {
    late SeriesRepository seriesRepository;
    late MockBox<Series> mockSeriesBox;
    late MockBox<Event> mockEventBox;

    setUp(() {
      mockSeriesBox = MockBox<Series>();
      mockEventBox = MockBox<Event>();
      seriesRepository = SeriesRepository(mockSeriesBox);
      
      // Stub the name property for mockEventBox
      when(mockEventBox.name).thenReturn('events');
    });

    test('addSeries adds a series to the box', () async {
      final Series series = Series(title: 'Test Series', events: HiveList(mockEventBox));
      when(mockSeriesBox.add(any)).thenAnswer((_) async => 0);
      
      await seriesRepository.addSeries(series);
      
      verify(mockSeriesBox.add(series)).called(1);
    });

    test('getAllSeries returns a list of series from the box', () {
      final List<Series> seriesList = <Series>[
        Series(title: 'Test Series 1', events: HiveList(mockEventBox)),
        Series(title: 'Test Series 2', events: HiveList(mockEventBox)),
      ];
      when(mockSeriesBox.values).thenReturn(seriesList);

      final List<Series> result = seriesRepository.getAllSeries();

      expect(result, equals(seriesList));
    });
  });
}
