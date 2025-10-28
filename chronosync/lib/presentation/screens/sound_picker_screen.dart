import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../data/models/device_sound.dart';
import '../../data/repositories/device_audio_repository.dart';

/// Screen for selecting a custom notification sound
class SoundPickerScreen extends StatefulWidget {
  final String? currentSoundPath;

  const SoundPickerScreen({
    super.key,
    this.currentSoundPath,
  });

  @override
  State<SoundPickerScreen> createState() => _SoundPickerScreenState();
}

class _SoundPickerScreenState extends State<SoundPickerScreen> {
  List<DeviceSound>? _sounds;
  bool _isLoading = true;
  String? _error;
  String? _playingSound;

  @override
  void initState() {
    super.initState();
    _loadSounds();
  }

  Future<void> _loadSounds() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repository = DeviceAudioRepository();
      final sounds = await repository.getAvailableSounds();
      
      if (mounted) {
        setState(() {
          _sounds = sounds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load sounds: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _previewSound(DeviceSound sound) async {
    final repository = DeviceAudioRepository();
    
    // Check if we're on a desktop platform
    if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      // Show a snackbar message on desktop
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Audio preview: ${sound.displayName}'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    
    // Stop any currently playing sound
    await repository.stopPreview();
    
    // Play the selected sound
    setState(() {
      _playingSound = sound.id;
    });
    
    await repository.previewSound(sound.filePath);
    
    // Auto-stop after a brief delay (simulating preview)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _playingSound == sound.id) {
        setState(() {
          _playingSound = null;
        });
      }
    });
  }

  Future<void> _stopPreview() async {
    final repository = DeviceAudioRepository();
    await repository.stopPreview();
    if (mounted) {
      setState(() {
        _playingSound = null;
      });
    }
  }

  @override
  void dispose() {
    // Stop any playing sound when leaving screen (but don't call setState)
    final repository = DeviceAudioRepository();
    repository.stopPreview(); // Call without await to avoid issues
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Sound'),
      ),
      body: Builder(
        builder: (context) {
          if (_isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadSounds,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (_sounds == null || _sounds!.isEmpty) {
            return const Center(
              child: Text('No sounds available'),
            );
          }

          return ListView.builder(
            itemCount: _sounds!.length,
            itemBuilder: (context, index) {
              final sound = _sounds![index];
              final isSelected = sound.filePath == widget.currentSoundPath;
              final isPlaying = _playingSound == sound.id;

              return ListTile(
                leading: Icon(
                  sound.isSystemSound ? Icons.phone_android : Icons.music_note,
                  color: isSelected ? Theme.of(context).primaryColor : null,
                ),
                title: Text(
                  sound.displayName,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.stop : Icons.play_arrow,
                        color: isPlaying ? Colors.red : null,
                      ),
                      onPressed: () {
                        if (isPlaying) {
                          _stopPreview();
                        } else {
                          _previewSound(sound);
                        }
                      },
                    ),
                    if (isSelected)
                      const Icon(Icons.check, color: Colors.green),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).pop(sound.filePath);
                },
              );
            },
          );
        },
      ),
    );
  }
}
