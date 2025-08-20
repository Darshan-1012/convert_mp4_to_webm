import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/log.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/session.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FFmpeg Kit - MP4 to WebM',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VideoConverterPage(),
    );
  }
}

class VideoConverterPage extends StatefulWidget {
  const VideoConverterPage({super.key});

  @override
  State<VideoConverterPage> createState() => _VideoConverterPageState();
}

class _VideoConverterPageState extends State<VideoConverterPage> {
  // Core state variables
  String logText = 'Select an MP4 file to convert to WebM...';
  bool isProcessing = false;
  String? inputFilePath;
  String? outputFilePath;

  // Progress tracking
  double progress = 0.0;
  String progressText = '';
  Duration? videoDuration;
  Duration processedDuration = Duration.zero;
  DateTime? conversionStartTime;
  Duration? estimatedTimeRemaining;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP4 to WebM Converter'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          _buildFileInfoSection(),
          _buildProgressSection(),
          _buildLogSection(),
        ],
      ),
      bottomNavigationBar: _buildButtonSection(),
    );
  }

  Widget _buildFileInfoSection() {
    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'File Information:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            inputFilePath != null
                ? 'Input: ${inputFilePath!.split('/').last}'
                : 'No file selected',
            style: const TextStyle(fontSize: 14),
          ),
          if (outputFilePath != null) ...[
            const SizedBox(height: 4),
            Text(
              'Output: ${outputFilePath!.split('/').last}',
              style: const TextStyle(fontSize: 14, color: Colors.green),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    if (!isProcessing) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress: ${(progress * 100).toStringAsFixed(1)}%'),
              if (estimatedTimeRemaining != null)
                Text('ETA: ${_formatDuration(estimatedTimeRemaining!)}'),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Text(progressText, style: const TextStyle(fontSize: 12)),
          if (videoDuration != null && processedDuration != Duration.zero) ...[
            const SizedBox(height: 4),
            Text(
              'Processed: ${_formatDuration(processedDuration)} / ${_formatDuration(videoDuration!)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLogSection() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(16.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: SingleChildScrollView(
          child: Text(
            logText,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonSection() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildActionButton(
              onPressed: isProcessing ? null : _selectFile,
              icon: Icons.file_open,
              label: 'Select',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              onPressed: _canConvert() ? () => _convertVideo('fast') : null,
              icon: Icons.speed,
              label: 'Fast',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              onPressed: _canConvert() ? () => _convertVideo('standard') : null,
              icon: Icons.video_file,
              label: 'Standard',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              onPressed: _canConvert()
                  ? () => _convertVideo('compressed')
                  : null,
              icon: Icons.compress,
              label: 'Compress',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              onPressed: _canConvert() ? () => _convertVideo('hardware') : null,
              icon: Icons.rocket_launch,
              label: 'Hardware',
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              onPressed: isProcessing ? null : _testWithSample,
              icon: Icons.play_arrow,
              label: 'Test',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      width: 80,
      height: 64,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.all(4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  bool _canConvert() => !isProcessing && inputFilePath != null;

  Future<void> _selectFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp4', 'mov', 'avi', 'mkv'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          inputFilePath = result.files.single.path!;
          outputFilePath = null;
          logText =
              'Selected: ${inputFilePath!.split('/').last}\nReady to convert...';
        });
      }
    } catch (e) {
      _updateLog('Error selecting file: $e');
    }
  }

  Future<void> _testWithSample() async {
    setState(() {
      isProcessing = true;
      logText = 'Loading sample video from assets...\n';
      _resetProgress();
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final sampleVideoRoot = await rootBundle.load('assets/sample_video.mp4');
      final sampleVideoFile = File('${tempDir.path}/sample_video.mp4');

      await sampleVideoFile.writeAsBytes(sampleVideoRoot.buffer.asUint8List());

      setState(() {
        inputFilePath = sampleVideoFile.path;
        logText +=
            'Sample video loaded: ${(sampleVideoRoot.lengthInBytes / 1024 / 1024).toStringAsFixed(2)} MB\n\n';
      });

      await _convertVideo('standard');
    } catch (e) {
      _updateLog(
        '❌ Error loading sample video: $e\nMake sure assets/sample_video.mp4 exists in your project.',
      );
      setState(() => isProcessing = false);
    }
  }

  Future<void> _convertVideo(String mode) async {
    if (inputFilePath == null) return;

    setState(() {
      isProcessing = true;
      conversionStartTime = DateTime.now();
      _resetProgress();
    });

    _updateLog('🚀 Starting MP4 to WebM conversion...\n');

    try {
      final tempDir = await getTemporaryDirectory();
      final inputFile = File(inputFilePath!);
      final fileName = inputFile.path.split('/').last.split('.').first;
      final outputFile = File('${tempDir.path}/${fileName}_converted.webm');

      if (outputFile.existsSync()) await outputFile.delete();

      await _getVideoDuration(inputFile.path);

      final conversionConfig = _getConversionConfig(
        mode,
        inputFile.path,
        outputFile.path,
      );

      _updateLog('Mode: ${conversionConfig['description']}\n');
      _updateLog('Input: ${inputFile.path.split('/').last}\n');
      _updateLog('Output: ${outputFile.path.split('/').last}\n');
      if (videoDuration != null) {
        _updateLog('Duration: ${_formatDuration(videoDuration!)}\n');
      }
      _updateLog('Command: ffmpeg ${conversionConfig['command']}\n\n');

      setState(() => progressText = 'Converting...');

      final startTime = DateTime.now();

      await FFmpegKit.executeAsync(
        conversionConfig['command']!,
        (Session session) async => await _handleSessionComplete(
          session,
          startTime,
          inputFile,
          outputFile,
        ),
        (Log log) => _handleLogMessage(log.getMessage()),
        (Statistics statistics) => _handleStatistics(statistics),
      );
    } catch (e) {
      _updateLog('❌ Error: $e');
      setState(() => isProcessing = false);
    }
  }

  Map<String, String> _getConversionConfig(
    String mode,
    String inputPath,
    String outputPath,
  ) {
    switch (mode) {
      case 'fast':
        return {
          'command':
              '-i "$inputPath" -c:v libvpx -crf 30 -b:v 1M -c:a libvorbis -preset ultrafast -threads 0 "$outputPath"',
          'description': 'Fast WebM (VP8 + Vorbis, Optimized)',
        };
      case 'standard':
        return {
          'command':
              '-i "$inputPath" -c:v libvpx-vp9 -crf 30 -b:v 0 -b:a 128k -c:a libopus "$outputPath"',
          'description': 'Standard WebM (VP9 + Opus)',
        };
      case 'compressed':
        return {
          'command':
              '-i "$inputPath" -c:v libvpx-vp9 -crf 40 -b:v 0 -b:a 96k -c:a libopus -preset slower "$outputPath"',
          'description': 'Compressed WebM (High compression)',
        };
      case 'hardware':
        if (Platform.isAndroid) {
          return {
            'command':
                '-i "$inputPath" -c:v h264_mediacodec -b:v 2M -c:a aac "$outputPath"',
            'description': 'Hardware WebM (Android MediaCodec)',
          };
        } else if (Platform.isIOS || Platform.isMacOS) {
          return {
            'command':
                '-i "$inputPath" -c:v h264_videotoolbox -b:v 2M -c:a aac "$outputPath"',
            'description': 'Hardware WebM (VideoToolbox)',
          };
        } else {
          return {
            'command':
                '-i "$inputPath" -c:v libvpx -crf 30 -b:v 1M -c:a libvorbis -preset ultrafast -threads 0 "$outputPath"',
            'description': 'Fast WebM (Software fallback)',
          };
        }
      default:
        return {
          'command':
              '-i "$inputPath" -c:v libvpx-vp9 -crf 30 -b:v 0 -b:a 128k -c:a libopus "$outputPath"',
          'description': 'Default WebM conversion',
        };
    }
  }

  Future<void> _getVideoDuration(String videoPath) async {
    try {
      final session = await FFmpegKit.execute('-i "$videoPath" -f null -');
      final output = await session.getOutput();

      if (output != null) {
        final durationMatch = RegExp(
          r'Duration: (\d+):(\d+):(\d+)\.(\d+)',
        ).firstMatch(output);
        if (durationMatch != null) {
          final hours = int.parse(durationMatch.group(1)!);
          final minutes = int.parse(durationMatch.group(2)!);
          final seconds = int.parse(durationMatch.group(3)!);
          final milliseconds = int.parse(durationMatch.group(4)!) * 10;

          videoDuration = Duration(
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          );
        }
      }
    } catch (e) {
      debugPrint('Error getting video duration: $e');
    }
  }

  Future<void> _handleSessionComplete(
    Session session,
    DateTime startTime,
    File inputFile,
    File outputFile,
  ) async {
    final returnCode = await session.getReturnCode();
    final duration = DateTime.now().difference(startTime);

    setState(() {
      if (ReturnCode.isSuccess(returnCode)) {
        logText += '\n✅ Conversion completed!\n';
        logText += 'Total time: ${duration.inSeconds}s\n';

        if (outputFile.existsSync()) {
          final inputSize = inputFile.lengthSync();
          final outputSize = outputFile.lengthSync();
          final compressionRatio = ((inputSize - outputSize) / inputSize * 100)
              .toStringAsFixed(1);

          logText +=
              'Input: ${(inputSize / 1024 / 1024).toStringAsFixed(2)} MB\n';
          logText +=
              'Output: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB\n';
          logText += 'Compression: $compressionRatio%\n';

          if (videoDuration != null) {
            final speedRatio = videoDuration!.inSeconds / duration.inSeconds;
            logText += 'Speed: ${speedRatio.toStringAsFixed(2)}x realtime\n';
          }

          outputFilePath = outputFile.path;
          progressText = 'Completed!';
          progress = 1.0;
        }
      } else {
        logText += '\n❌ Conversion failed! Return code: $returnCode\n';
        progressText = 'Failed';
      }
      isProcessing = false;
    });
  }

  void _handleLogMessage(String message) {
    setState(() => logText += message);
    _parseProgressFromLog(message);
  }

  void _handleStatistics(Statistics statistics) {
    final timeMs = statistics.getTime();
    final size = statistics.getSize();

    if (timeMs > 0) {
      setState(() {
        processedDuration = Duration(milliseconds: timeMs);

        if (videoDuration != null && videoDuration!.inMilliseconds > 0) {
          progress = (timeMs / videoDuration!.inMilliseconds).clamp(0.0, 1.0);
          _calculateETA();
        }

        progressText =
            'Time: ${_formatDuration(processedDuration)}, Size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB';
      });
    }
  }

  void _parseProgressFromLog(String message) {
    final timeMatch = RegExp(
      r'time=(\d+):(\d+):(\d+)\.(\d+)',
    ).firstMatch(message);
    if (timeMatch != null) {
      final hours = int.parse(timeMatch.group(1)!);
      final minutes = int.parse(timeMatch.group(2)!);
      final seconds = int.parse(timeMatch.group(3)!);
      final milliseconds = int.parse(timeMatch.group(4)!) * 10;

      setState(() {
        processedDuration = Duration(
          hours: hours,
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        if (videoDuration != null && videoDuration!.inMilliseconds > 0) {
          progress =
              (processedDuration.inMilliseconds / videoDuration!.inMilliseconds)
                  .clamp(0.0, 1.0);
          _calculateETA();
        }
      });
    }
  }

  void _calculateETA() {
    if (progress > 0.05 && conversionStartTime != null) {
      final elapsedTime = DateTime.now().difference(conversionStartTime!);
      final totalEstimatedTime = Duration(
        milliseconds: (elapsedTime.inMilliseconds / progress).round(),
      );
      estimatedTimeRemaining = totalEstimatedTime - elapsedTime;

      if (estimatedTimeRemaining!.isNegative) {
        estimatedTimeRemaining = Duration.zero;
      }
    }
  }

  void _resetProgress() {
    progress = 0.0;
    progressText = 'Starting...';
    videoDuration = null;
    processedDuration = Duration.zero;
    estimatedTimeRemaining = null;
  }

  void _updateLog(String message) {
    setState(() => logText += message);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$minutes:$seconds";
    }
    return "$minutes:$seconds";
  }
}
