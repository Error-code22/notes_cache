import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// Audio player with play/pause/seek + progress (audioplayers).
class AudioPlayerPage extends StatefulWidget {
  final File file;
  final String title;

  const AudioPlayerPage({super.key, required this.file, required this.title});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = true;
  bool _playing = false;
  String? _error;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<void>? _completeSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      _completeSub = _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });

      await _player.play(DeviceFileSource(widget.file.path));
      if (mounted) setState(() {
        _playing = true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      await _player.resume();
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Could not play audio.\n$_error', textAlign: TextAlign.center))
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withOpacity(0.1),
                          ),
                          child: Icon(Icons.music_note_rounded, size: 72, color: theme.colorScheme.primary),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          widget.title,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 24),
                        Slider(
                          value: _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds)
                              .toDouble(),
                          max: _duration.inMilliseconds == 0 ? 1.0 : _duration.inMilliseconds.toDouble(),
                          onChanged: (v) async {
                            await _player.seek(Duration(milliseconds: v.round()));
                            if (mounted) setState(() => _position = Duration(milliseconds: v.round()));
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmt(_position), style: theme.textTheme.bodySmall),
                            Text(_fmt(_duration), style: theme.textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 24),
                        IconButton(
                          iconSize: 64,
                          icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          color: theme.colorScheme.primary,
                          onPressed: _toggle,
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
