/// Mirrors the defect shape returned by the backend's video pipeline
/// (see video_routes.py process_video_job).
class VideoDefect {
  final int frameIndex;
  final String type;
  final String severity;
  final double confidence;
  final double areaMm2;
  final double timestampSec;
  final List<int> bbox; // [x, y, w, h]

  VideoDefect({
    required this.frameIndex,
    required this.type,
    required this.severity,
    required this.confidence,
    required this.areaMm2,
    required this.timestampSec,
    required this.bbox,
  });

  factory VideoDefect.fromJson(Map<String, dynamic> json) {
    // ✅ Safely parse bbox array to prevent TypeError on malformed data
    List<int> parsedBbox = [];
    if (json['bbox'] is List) {
      parsedBbox = (json['bbox'] as List)
          .map((e) => (e as num).toInt())
          .toList();
    }

    return VideoDefect(
      // ✅ Use 'as num' to safely handle both int and double from JSON
      frameIndex: (json['frame_index'] as num?)?.toInt() ?? 0,
      type: json['type']?.toString() ?? 'Unknown',
      severity: json['severity']?.toString() ?? 'MINOR',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      areaMm2: (json['area_mm2'] as num?)?.toDouble() ?? 0.0,
      timestampSec: (json['timestamp_sec'] as num?)?.toDouble() ?? 0.0,
      bbox: parsedBbox,
    );
  }

  @override
  String toString() {
    return 'VideoDefect(type: $type, confidence: $confidence, timestamp: $timestampSec)';
  }
}

/// status: queued | processing | training | done | completed | failed
class VideoJobStatus {
  final String jobId;
  final String status;
  final double progress;
  final String? decision;      // Overall decision: ACCEPT | REVIEW | REJECT
  final int defectCount;
  final List<VideoDefect> defects;
  final String? error;
  final String? videoUrl;

  VideoJobStatus({
    required this.jobId,
    required this.status,
    required this.progress,
    this.decision,
    required this.defectCount,
    required this.defects,
    this.error,
    this.videoUrl,
  });

  // ✅ Expanded to catch slight variations in backend status strings
  bool get isDone => status == 'done' || status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isInProgress => status == 'queued' || status == 'processing' || status == 'training';

  factory VideoJobStatus.fromJson(Map<String, dynamic> json) {
    // ✅ Safely parse defects list, filtering out any non-Map items
    List<VideoDefect> parsedDefects = [];
    if (json['defects'] is List) {
      parsedDefects = (json['defects'] as List)
          .whereType<Map<String, dynamic>>()
          .map((d) => VideoDefect.fromJson(d))
          .toList();
    }

    return VideoJobStatus(
      jobId: json['job_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'queued',
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      decision: json['decision']?.toString(),
      defectCount: (json['defect_count'] as num?)?.toInt() ?? 0,
      defects: parsedDefects,
      error: json['error']?.toString(),
      videoUrl: json['video_url']?.toString(),
    );
  }

  @override
  String toString() {
    return 'VideoJobStatus(jobId: $jobId, status: $status, progress: $progress%, defects: $defectCount)';
  }
}