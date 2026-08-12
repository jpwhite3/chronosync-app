import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

@HiveType(typeId: 2)
class UserPreferences extends HiveObject {
  @HiveField(0)
  String swipeDirection; // 'ltr' or 'rtl'

  @HiveField(1)
  bool autoProgressAudioEnabled;

  UserPreferences({
    this.swipeDirection = 'ltr',
    this.autoProgressAudioEnabled = true,
  });

  SwipeDirection get swipeDirectionEnum =>
      swipeDirection == 'rtl' ? SwipeDirection.rtl : SwipeDirection.ltr;
}

enum SwipeDirection {
  ltr,
  rtl;

  String get value => name;

  DismissDirection get dismissDirection =>
      this == ltr ? DismissDirection.startToEnd : DismissDirection.endToStart;
}

/// Frozen adapter used to read the pre-Drift preferences during migration.
final class UserPreferencesAdapter extends TypeAdapter<UserPreferences> {
  @override
  int get typeId => 2;

  @override
  UserPreferences read(BinaryReader reader) {
    final int fieldCount = reader.readByte();
    final Map<int, dynamic> fields = <int, dynamic>{
      for (int index = 0; index < fieldCount; index += 1)
        reader.readByte(): reader.read(),
    };
    return UserPreferences(
      swipeDirection: fields[0] as String? ?? 'ltr',
      autoProgressAudioEnabled: fields[1] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, UserPreferences object) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(object.swipeDirection)
      ..writeByte(1)
      ..write(object.autoProgressAudioEnabled);
  }
}
