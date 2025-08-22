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
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Converter Pro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: VideoConverterPage(cameras: cameras),
    );
  }
}

class VideoConverterPage extends StatefulWidget {
  final List<CameraDescription> cameras;

  const VideoConverterPage({super.key, required this.cameras});

  @override
  State<VideoConverterPage> createState() => _VideoConverterPageState();
}

class _VideoConverterPageState extends State<VideoConverterPage>
    with WidgetsBindingObserver {
  // Camera variables
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isRecording = false;
  String? _recordedVideoPath;

  // Core state variables
  String logText = 'Initialize camera or select an MP4 file to convert...';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    final cameraPermission = await Permission.camera.request();
    final micPermission = await Permission.microphone.request();

    if (cameraPermission != PermissionStatus.granted ||
        micPermission != PermissionStatus.granted) {
      setState(() {
        logText =
            '❌ Camera/microphone permission denied. Grant permissions in settings.';
      });
      return;
    }

    if (widget.cameras.isEmpty) {
      setState(() => logText = '❌ No cameras available.');
      return;
    }

    try {
      _cameraController = CameraController(
        widget.cameras[0],
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          logText =
              '📷 Camera ready. Start recording or select existing video.';
        });
      }
    } catch (e) {
      setState(() => logText = '❌ Camera error: $e');
    }
  }

  Future<void> _startRecording() async {
    if (!_isCameraInitialized || _isRecording) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final videoPath = '${appDir.path}/video_$timestamp.mp4';

      _recordedVideoPath = videoPath;
      await _cameraController!.startVideoRecording();

      setState(() {
        _isRecording = true;
        logText += '\n🔴 Recording started...';
      });
    } catch (e) {
      setState(() => logText += '\n❌ Recording error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final permanentPath = '${appDir.path}/recorded_$timestamp.mp4';

      final sourceFile = File(videoFile.path);
      await sourceFile.copy(permanentPath);

      setState(() {
        _isRecording = false;
        _recordedVideoPath = permanentPath;
        inputFilePath = permanentPath;
        logText += '\n⏹️ Recording saved! Ready to convert.';
      });
    } catch (e) {
      setState(() {
        _isRecording = false;
        logText += '\n❌ Stop recording error: $e';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (!_isCameraInitialized || widget.cameras.length < 2) return;

    try {
      final currentCamera = _cameraController!.description;
      final newCamera = widget.cameras.firstWhere(
        (camera) => camera != currentCamera,
        orElse: () => widget.cameras[0],
      );

      await _cameraController!.dispose();
      _cameraController = CameraController(
        newCamera,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => logText += '\n📷 Camera switched');
    } catch (e) {
      setState(() => logText += '\n❌ Camera switch error: $e');
    }
  }

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
          logText += '\n📁 Selected: ${inputFilePath!.split('/').last}';
        });
      }
    } catch (e) {
      _updateLog('\n❌ File selection error: $e');
    }
  }

  Future<void> _convertVideo(String mode) async {
    if (inputFilePath == null) {
      _updateLog('\n❌ No input file selected');
      return;
    }

    final inputFile = File(inputFilePath!);
    if (!await inputFile.exists()) {
      _updateLog('\n❌ Input file not found');
      return;
    }

    setState(() {
      isProcessing = true;
      conversionStartTime = DateTime.now();
      _resetProgress();
    });

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = inputFile.path.split('/').last.split('.').first;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      String outputExtension = mode.startsWith('webm_') ? 'webm' : 'mp4';
      final outputFile = File(
        '${appDir.path}/${fileName}_${mode}_$timestamp.$outputExtension',
      );

      await _getVideoDuration(inputFile.path);

      final conversionConfig = _getConversionConfig(
        mode,
        inputFile.path,
        outputFile.path,
      );

      _updateLog('\n🚀 Converting to ${outputExtension.toUpperCase()}...');
      _updateLog('🔧 Mode: ${conversionConfig['description']}');

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
      _updateLog('\n❌ Conversion error: $e');
      setState(() => isProcessing = false);
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
      if (ReturnCode.isSuccess(returnCode) && outputFile.existsSync()) {
        final inputSize = inputFile.lengthSync();
        final outputSize = outputFile.lengthSync();

        if (outputSize > 0) {
          final compressionRatio = ((inputSize - outputSize) / inputSize * 100)
              .toStringAsFixed(1);

          _updateLog('\n✅ Conversion completed!');
          _updateLog('⏱️ Time: ${duration.inSeconds}s');
          _updateLog(
            '📊 Input: ${(inputSize / 1024 / 1024).toStringAsFixed(2)} MB',
          );
          _updateLog(
            '📊 Output: ${(outputSize / 1024 / 1024).toStringAsFixed(2)} MB',
          );
          _updateLog('📊 Compression: $compressionRatio%');

          outputFilePath = outputFile.path;
          progressText = 'Conversion completed!';
          progress = 1.0;
        } else {
          _updateLog('❌ Output file is empty');
        }
      } else {
        _updateLog('\n❌ Conversion failed!');
        progressText = 'Conversion failed';
      }
      isProcessing = false;
    });
  }

  // SAVE TO GALLERY FUNCTIONALITY
  Future<void> _saveToGallery() async {
    if (outputFilePath == null) {
      _showMessage('No converted file to save');
      return;
    }

    try {
      _updateLog('\n💾 Saving to gallery...');

      // Request permissions
      if (Platform.isAndroid) {
        if (!(await Gal.hasAccess())) {
          final hasAccess = await Gal.requestAccess();
          if (!hasAccess) {
            _showMessage('Gallery permission denied');
            return;
          }
        }
      }

      await Gal.putVideo(outputFilePath!);

      _updateLog('\n✅ Video saved to gallery!');
      _showMessage('Video saved to gallery successfully!');
    } catch (e) {
      _updateLog('\n❌ Save error: $e');
      _showMessage('Error saving to gallery: $e');
    }
  }

  // SHARE FUNCTIONALITY
  Future<void> _shareVideo() async {
    if (outputFilePath == null) {
      _showMessage('No converted file to share');
      return;
    }

    try {
      _updateLog('\n📤 Sharing video...');

      final file = File(outputFilePath!);
      if (!await file.exists()) {
        _showMessage('File not found');
        return;
      }

      final fileName = outputFilePath!.split('/').last;
      await Share.shareXFiles(
        [XFile(outputFilePath!)],
        text: 'Converted video: $fileName',
        subject: 'Video Conversion Complete',
      );

      _updateLog('\n📤 Share dialog opened');
    } catch (e) {
      _updateLog('\n❌ Share error: $e');
      _showMessage('Error sharing video: $e');
    }
  }

  // COPY PATH TO CLIPBOARD
  Future<void> _copyPath() async {
    if (outputFilePath == null) {
      _showMessage('No file path to copy');
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: outputFilePath!));
      _updateLog('\n📋 File path copied to clipboard');
      _showMessage('File path copied to clipboard');
    } catch (e) {
      _updateLog('\n❌ Copy error: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Map<String, String> _getConversionConfig(
    String mode,
    String inputPath,
    String outputPath,
  ) {
    final escapedInput = inputPath.replaceAll('"', '\\"');
    final escapedOutput = outputPath.replaceAll('"', '\\"');
    final threadCount = Platform.numberOfProcessors;

    switch (mode) {
      case 'webm_fast': // NEW: Fastest WebM possible
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libvpx ' // VP8 is faster than VP9
              '-quality realtime ' // Realtime quality for speed
              '-cpu-used 8 ' // Maximum speed (0-16, higher = faster)
              '-deadline realtime ' // Realtime deadline
              '-threads $threadCount '
              '-crf 40 ' // Higher CRF = faster + smaller
              '-b:v 500k ' // Lower bitrate = faster
              '-g 30 ' // Keyframe every 30 frames
              '-c:a libvorbis ' // Fast audio codec
              '-b:a 64k ' // Low audio bitrate
              '-ac 1 ' // Mono audio (faster)
              '-ar 22050 ' // Lower sample rate
              '-f webm '
              '-y '
              '"$escapedOutput"',
          'description': 'Ultra Fast WebM (VP8 + Vorbis)',
        };

      case 'webm_turbo': // NEW: Balanced WebM
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libvpx '
              '-quality good '
              '-cpu-used 6 '
              '-deadline realtime '
              '-threads $threadCount '
              '-crf 35 '
              '-b:v 800k '
              '-g 30 '
              '-c:a libvorbis '
              '-b:a 96k '
              '-f webm '
              '-y '
              '"$escapedOutput"',
          'description': 'Turbo WebM (Better Quality)',
        };

      case 'webm_standard': // Standard WebM
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libvpx-vp9 ' // VP9 for better compression
              '-crf 30 '
              '-b:v 1000k '
              '-cpu-used 4 ' // Balanced speed
              '-threads $threadCount '
              '-row-mt 1 ' // Enable row-based multithreading
              '-c:a libopus ' // Better audio codec
              '-b:a 128k '
              '-f webm '
              '-y '
              '"$escapedOutput"',
          'description': 'Standard WebM (VP9 + Opus)',
        };

      case 'webm_copy_audio': // NEW: Copy audio for speed
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libvpx '
              '-quality realtime '
              '-cpu-used 8 '
              '-deadline realtime '
              '-threads $threadCount '
              '-crf 40 '
              '-b:v 400k '
              '-c:a copy ' // Try to copy audio (may not work with all inputs)
              '-f webm '
              '-y '
              '"$escapedOutput"',
          'description': 'Fast WebM (Copy Audio if Compatible)',
        };

      // Keep the MP4 fast options
      case 'lightning':
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libx264 '
              '-preset ultrafast '
              '-tune zerolatency '
              '-crf 28 '
              '-threads $threadCount '
              '-c:a copy '
              '-f mp4 '
              '-y '
              '"${escapedOutput.replaceAll('.webm', '.mp4')}"',
          'description': 'Lightning MP4 (Ultra Fast)',
        };

      case 'copy':
        return {
          'command':
              '-i "$escapedInput" '
              '-c copy '
              '-f mp4 '
              '-y '
              '"${escapedOutput.replaceAll('.webm', '.mp4')}"',
          'description': 'Instant Copy (MP4)',
        };

      case 'rocket':
        if (Platform.isAndroid) {
          return {
            'command':
                '-hwaccel auto '
                '-i "$escapedInput" '
                '-c:v h264_mediacodec '
                '-b:v 2000k '
                '-c:a copy '
                '-f mp4 '
                '-y '
                '"${escapedOutput.replaceAll('.webm', '.mp4')}"',
            'description': 'Rocket MP4 (Android Hardware)',
          };
        } else {
          return {
            'command':
                '-i "$escapedInput" '
                '-c:v libx264 '
                '-preset ultrafast '
                '-crf 28 '
                '-threads $threadCount '
                '-c:a copy '
                '-f mp4 '
                '-y '
                '"${escapedOutput.replaceAll('.webm', '.mp4')}"',
            'description': 'Rocket MP4 (Software)',
          };
        }

      default:
        return {
          'command':
              '-i "$escapedInput" '
              '-c:v libvpx '
              '-quality realtime '
              '-cpu-used 8 '
              '-threads $threadCount '
              '-crf 40 '
              '-c:a libvorbis '
              '-b:a 64k '
              '-f webm '
              '-y '
              '"$escapedOutput"',
          'description': 'Default Fast WebM',
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Converter Pro'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildCameraSection(),
            _buildFileInfoSection(),
            if (isProcessing) _buildProgressSection(),
            _buildLogSection(),
          ],
        ),
      ),
      bottomNavigationBar: _buildButtonSection(),
    );
  }

  Widget _buildCameraSection() {
    return Container(
      height: 200,
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12.0),
        child: _isCameraInitialized
            ? Stack(
                children: [
                  CameraPreview(_cameraController!),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _isRecording ? '🔴 REC' : '📷 READY',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                color: Colors.grey.shade200,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.camera_alt, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'Camera not available',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFileInfoSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'File Info:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            inputFilePath != null
                ? 'Input: ${inputFilePath!.split('/').last}'
                : 'No file selected',
          ),
          if (outputFilePath != null) ...[
            const SizedBox(height: 4),
            Text(
              'Output: ${outputFilePath!.split('/').last}',
              style: const TextStyle(color: Colors.green),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
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
        ],
      ),
    );
  }

  Widget _buildLogSection() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: SingleChildScrollView(
          child: Text(
            logText,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonSection() {
    return Container(
      height: 160,
      padding: const EdgeInsets.all(8.0),
      child: SafeArea(
        child: Column(
          children: [
            // Camera controls
            Row(
              children: [
                Expanded(
                  child: _buildButton(
                    'Record',
                    Icons.videocam,
                    _isCameraInitialized && !_isRecording && !isProcessing
                        ? _startRecording
                        : null,
                    Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'Stop',
                    Icons.stop,
                    _isRecording ? _stopRecording : null,
                    Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'Flip',
                    Icons.flip_camera_android,
                    _isCameraInitialized &&
                            !_isRecording &&
                            widget.cameras.length > 1
                        ? _switchCamera
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'Select',
                    Icons.file_open,
                    !isProcessing ? _selectFile : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Conversion controls
            Row(
              children: [
                Expanded(
                  child: _buildButton(
                    'WebM Fast',
                    Icons.rocket_launch,
                    _canConvert() ? () => _convertVideo('webm_fast') : null,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'WebM Turbo',
                    Icons.speed,
                    _canConvert() ? () => _convertVideo('webm_turbo') : null,
                    Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'MP4 Copy',
                    Icons.flash_on,
                    _canConvert() ? () => _convertVideo('copy') : null,
                    Colors.amber,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'MP4 Fast',
                    Icons.bolt,
                    _canConvert() ? () => _convertVideo('fast') : null,
                    Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Save/Share controls
            Row(
              children: [
                Expanded(
                  child: _buildButton(
                    'Save Gallery',
                    Icons.save,
                    outputFilePath != null ? _saveToGallery : null,
                    Colors.purple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'Share',
                    Icons.share,
                    outputFilePath != null ? _shareVideo : null,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildButton(
                    'Copy Path',
                    Icons.content_copy,
                    outputFilePath != null ? _copyPath : null,
                    Colors.indigo,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(
    String label,
    IconData icon,
    VoidCallback? onPressed, [
    Color? color,
  ]) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: color,
          foregroundColor: color != null ? Colors.white : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14),
            Text(
              label,
              style: const TextStyle(fontSize: 8),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  bool _canConvert() => !isProcessing && !_isRecording && inputFilePath != null;

  // Helper methods
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
      debugPrint('Duration error: $e');
    }
  }

  void _handleLogMessage(String message) {
    setState(() => logText += message);
    _parseProgressFromLog(message);
  }

  void _handleStatistics(Statistics statistics) {
    final timeMs = statistics.getTime();
    if (timeMs > 0) {
      setState(() {
        processedDuration = Duration(milliseconds: timeMs);
        if (videoDuration != null && videoDuration!.inMilliseconds > 0) {
          progress = (timeMs / videoDuration!.inMilliseconds).clamp(0.0, 1.0);
          _calculateETA();
        }
        progressText = 'Time: ${_formatDuration(processedDuration)}';
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
      if (estimatedTimeRemaining!.isNegative)
        estimatedTimeRemaining = Duration.zero;
    }
  }

  void _resetProgress() {
    progress = 0.0;
    progressText = 'Starting...';
    videoDuration = null;
    processedDuration = Duration.zero;
    estimatedTimeRemaining = null;
  }

  void _updateLog(String message) => setState(() => logText += message);

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0
        ? "${twoDigits(duration.inHours)}:$minutes:$seconds"
        : "$minutes:$seconds";
  }
}
