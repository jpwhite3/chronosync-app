import 'package:equatable/equatable.dart';

/// Represents an available device notification sound
class DeviceSound extends Equatable {
  final String id;
  final String displayName;
  final String filePath;
  final bool isSystemSound;

  const DeviceSound({
    required this.id,
    required this.displayName,
    required this.filePath,
    this.isSystemSound = false,
  });

  /// Default system notification sound
  factory DeviceSound.systemDefault() {
    return const DeviceSound(
      id: 'system_default',
      displayName: 'System Default',
      filePath: 'system_default',
      isSystemSound: true,
    );
  }

  @override
  List<Object?> get props => [id, displayName, filePath, isSystemSound];
}
