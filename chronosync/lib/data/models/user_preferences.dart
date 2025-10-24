import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

part 'user_preferences.g.dart';

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
