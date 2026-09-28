import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../services.dart';

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
  bool _transcribing = false;
  Map<String, dynamic>? _transcript;

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

  Future<void> _transcribe() async {
    if (_transcribing) return;
    setState(() => _transcribing = true);
    final result = await NoteService().transcribeAudio(widget.file);
    if (!mounted) return;
    setState(() {
      _transcribing = false;
      if (result['error'] == null && (result['text'] ?? '').toString().isNotEmpty) {
        _transcript = result;
      } else {
        _transcript = {'error': (result['error'] ?? 'Empty transcript').toString()};
      }
    });
    if (_transcript?.containsKey('error') == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_transcript!['error']}')),
      );
    }
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
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _transcribing ? null : _transcribe,
                          icon: _transcribing
                              ? const SizedBox(
                                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.subtitles_rounded),
                          label: Text(_transcribing ? 'Transcribing…' : 'Transcribe'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        if (_transcript != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            width: double.maxFinite,
                            constraints: const BoxConstraints(maxHeight: 260),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: theme.dividerColor),
                            ),
                            child: SingleChildScrollView(
                              child: _transcript!['error'] != null
                                  ? Text('${_transcript!['error']}',
                                      style: const TextStyle(color: Colors.red, fontSize: 13))
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_transcript!['events'] is List &&
                                            (_transcript!['events'] as List).isNotEmpty) ...[
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: (_transcript!['events'] as List)
                                                .map((e) => Chip(
                                                      visualDensity: VisualDensity.compact,
                                                      label: Text(
                                                        '${e['time'] ?? ''} ${e['type'] ?? ''}'
                                                            .trim(),
                                                        style: const TextStyle(fontSize: 11),
                                                      ),
                                                    ))
                                                .toList(),
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                        Text(
                                          _transcript!['text']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 14, height: 1.5),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          [
                                            if (_transcript!['diarized'] == true) 'Speakers distinguished',
                                            if (_transcript!['usedFallback'] == true)
                                              'Fallback: ${_transcript!['model'] ?? 'whisper'}',
                                            if ((_transcript!['note'] ?? '').toString().isNotEmpty)
                                              '${_transcript!['note']}',
                                          ].join('  ·  '),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(color: theme.hintColor),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }
}
