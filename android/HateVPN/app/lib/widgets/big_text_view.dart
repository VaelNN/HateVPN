import 'dart:convert';

import 'package:flutter/material.dart';
import 'safe_bottom.dart';














const int kBigTextChunkChars = 4096;

List<String> chunkTextLines(String text, {int maxChunk = kBigTextChunkChars}) {
  final out = <String>[];
  for (final line in const LineSplitter().convert(text)) {
    if (line.length <= maxChunk) {
      out.add(line);
      continue;
    }
    for (var i = 0; i < line.length; i += maxChunk) {
      out.add(line.substring(
          i, i + maxChunk > line.length ? line.length : i + maxChunk));
    }
  }
  return out;
}



class BigTextView extends StatefulWidget {
  const BigTextView({
    super.key,
    required this.text,
    this.style,
    this.padding = const EdgeInsets.all(12),
  });

  final String text;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;

  @override
  State<BigTextView> createState() => _BigTextViewState();
}

class _BigTextViewState extends State<BigTextView> {
  late List<String> _chunks;

  @override
  void initState() {
    super.initState();
    _chunks = chunkTextLines(widget.text);
  }

  @override
  void didUpdateWidget(BigTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _chunks = chunkTextLines(widget.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: ListView.builder(
        padding: widget.padding.withSafeBottom(context),
        itemCount: _chunks.length,
        itemBuilder: (context, i) => Text(


          _chunks[i].isEmpty ? ' ' : _chunks[i],
          style: widget.style,
        ),
      ),
    );
  }
}



class BigTextSliver extends StatefulWidget {
  const BigTextSliver({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<BigTextSliver> createState() => _BigTextSliverState();
}

class _BigTextSliverState extends State<BigTextSliver> {
  late List<String> _chunks;

  @override
  void initState() {
    super.initState();
    _chunks = chunkTextLines(widget.text);
  }

  @override
  void didUpdateWidget(BigTextSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _chunks = chunkTextLines(widget.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SliverList.builder(
      itemCount: _chunks.length,
      itemBuilder: (context, i) => Text(
        _chunks[i].isEmpty ? ' ' : _chunks[i],
        style: widget.style,
      ),
    );
  }
}
