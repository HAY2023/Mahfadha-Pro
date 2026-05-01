import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();

  Future<void> playConnectSound() async {
    // Generate or use a bundled asset. 
    // Assuming user will provide 'sounds/connect.mp3' in assets.
    try {
      await _player.play(AssetSource('sounds/connect.mp3'));
    } catch (_) {}
  }

  Future<void> playErrorSound() async {
    try {
      await _player.play(AssetSource('sounds/error.mp3'));
    } catch (_) {}
  }

  Future<void> playInjectSound() async {
    try {
      await _player.play(AssetSource('sounds/inject.mp3'));
    } catch (_) {}
  }
}
