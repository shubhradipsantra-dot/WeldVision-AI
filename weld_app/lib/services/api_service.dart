import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'auth_service.dart';
import '../models/video_inspection_models.dart';
import '../config/app_config.dart';

class ApiService {
  /// All API traffic goes to the local FastAPI backend via [AppConfig.baseUrl].
  String get baseUrl => AppConfig.baseUrl;

  final AuthService _authService = AuthService();

  Future<Map<String, String>> _getAuthHeaders({bool isMultipart = false}) async {
    final token = await _authService.getToken();
    if (isMultipart) {
      // For multipart, http package sets Content-Type automatically with boundary.
      // Only add Authorization if we have a token (backend accepts anonymous too).
      if (token != null) {
        return {'Authorization': 'Bearer $token'};
      }
      return {};
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // ========================================================
  // 📷 IMAGE PREDICTION
  // POST /predict-image  →  { success, decision:{decision,defects,error}, image_url }
  // ========================================================
  Future<Map<String, dynamic>> predictImage(File imageFile, {String? modelName}) async {
    final headers = await _getAuthHeaders(isMultipart: true);
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict-image'));

    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath(
      'file', imageFile.path, contentType: MediaType('image', 'jpeg'),
    ));

    if (modelName != null && modelName.isNotEmpty) {
      request.fields['model_name'] = modelName;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Prediction failed (${response.statusCode}): ${response.body}');
  }

  // ========================================================
  // 📹 LIVE FRAME PREDICTION
  // POST /predict-frame  →  { decision, defects, image_width, image_height, error }
  // ========================================================
  Future<Map<String, dynamic>> predictFrame(File imageFile, {String? modelName}) async {
    final headers = await _getAuthHeaders(isMultipart: true);
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/predict-frame'));

    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath(
      'file', imageFile.path, contentType: MediaType('image', 'jpeg'),
    ));

    if (modelName != null && modelName.isNotEmpty) {
      request.fields['model_name'] = modelName;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Frame prediction failed (${response.statusCode}): ${response.body}');
  }

  // ========================================================
  // 🎥 VIDEO PREDICTION (async job)
  // POST /predict-video  →  { success, job_id }
  // GET  /video-status/{job_id}  →  VideoJobStatus
  // GET  /video-result/{job_id}  →  mp4 file
  // ========================================================
  Future<String> uploadVideo(File videoFile, {String? modelName}) async {
    final uri = Uri.parse('$baseUrl/predict-video');
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(await _getAuthHeaders(isMultipart: true));
    if (modelName != null && modelName.isNotEmpty) {
      request.fields['model_name'] = modelName;
    }

    request.files.add(await http.MultipartFile.fromPath(
      'file', videoFile.path, contentType: MediaType('video', 'mp4'),
    ));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final jobId = body['job_id'] as String?;
    if (jobId == null) throw Exception('Backend did not return a job_id');
    return jobId;
  }

  Future<VideoJobStatus> getVideoStatus(String jobId) async {
    final uri = Uri.parse('$baseUrl/video-status/$jobId');
    final headers = await _getAuthHeaders();
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    if (response.statusCode != 200) {
      throw Exception('Status check failed (${response.statusCode}): ${response.body}');
    }

    return VideoJobStatus.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Full URL to stream / download the processed video for [jobId].
  String getVideoResultUrl(String jobId) => '$baseUrl/video-result/$jobId';

  // ========================================================
  // 🧠 MODEL TRAINING
  // POST /train-model         (video upload)
  // POST /train-model-images  (image folder upload)
  // GET  /training-status/{job_id}
  // POST /rename-model
  // ========================================================

  /// Upload a video file and start a training job.
  /// Returns { success: true, job_id: "..." }
  Future<Map<String, dynamic>> trainModel(
    File videoFile, {
    void Function(double progress)? onProgress,
  }) async {
    final uri = Uri.parse('$baseUrl/train-model');
    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(await _getAuthHeaders(isMultipart: true));
    request.files.add(await http.MultipartFile.fromPath(
      'file', videoFile.path, contentType: MediaType('video', 'mp4'),
    ));

    // For large videos the upload itself may take a while — notify progress
    // based on bytes sent (approximate, since http doesn't expose send progress).
    final streamed = await request.send();
    onProgress?.call(1.0); // upload done

    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Training failed (${response.statusCode}): ${response.body}');
  }

  /// Upload a list of image files and start a training job.
  Future<Map<String, dynamic>> trainModelImages(List<File> imageFiles) async {
    final headers = await _getAuthHeaders(isMultipart: true);
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/train-model-images'));

    request.headers.addAll(headers);
    for (final file in imageFiles) {
      request.files.add(await http.MultipartFile.fromPath(
        'files', file.path, contentType: MediaType('image', 'jpeg'),
      ));
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Training failed (${response.statusCode}): ${response.body}');
  }

  /// Poll training status.
  /// Returns { status, progress, model_path, model_name, error }
  Future<Map<String, dynamic>> checkTrainingStatus(String jobId) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/training-status/$jobId'),
      headers: headers,
    );

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to check status (${response.statusCode}): ${response.body}');
  }

  // ========================================================
  // 📊 DATA & STATS
  // GET /models              →  { models: [ { model_name, name, created_at, ... } ] }
  // GET /inspections/recent  →  { inspections: [ ... ] }
  // GET /stats               →  { inspections_today, pass_rate, avg_defects }
  // ========================================================

  /// Returns a list of model maps.  Each map has at least 'name' / 'model_name'.
  Future<List<dynamic>> getModels() async {
    final headers = await _getAuthHeaders();
    final response = await http.get(Uri.parse('$baseUrl/models'), headers: headers);

    if (response.statusCode != 200) {
      if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
      throw Exception('Failed to load models (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    // Backend returns { "models": [...] } — extract the list.
    if (data is Map && data.containsKey('models')) return data['models'] as List;
    // Fallback: backend returned a bare list (older schema).
    if (data is List) return data;
    return [];
  }

  Future<List<dynamic>> getRecentInspections({int limit = 20}) async {
    final headers = await _getAuthHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/inspections/recent?limit=$limit'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['inspections'] ?? [];
    }
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to load inspections (${response.statusCode}): ${response.body}');
  }

  Future<Map<String, dynamic>> getStats() async {
    final headers = await _getAuthHeaders();
    final response = await http.get(Uri.parse('$baseUrl/stats'), headers: headers);

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to load stats (${response.statusCode}): ${response.body}');
  }

  // ========================================================
  // 🗑️ MODEL MANAGEMENT
  // DELETE /models/{model_name}         →  { success }
  // PATCH  /models/{model_name}/rename  →  { success, old_name, new_name }
  // POST   /rename-model                →  { success, model_name, model_path }
  // ========================================================

  Future<bool> deleteModel(String modelName) async {
    final headers = await _getAuthHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/models/$modelName'),
      headers: headers,
    );

    if (response.statusCode == 200) return true;
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to delete model (${response.statusCode}): ${response.body}');
  }

  Future<bool> renameModel(String oldName, String newName) async {
    final headers = await _getAuthHeaders();
    final response = await http.patch(
      Uri.parse('$baseUrl/models/$oldName/rename'),
      headers: headers,
      body: jsonEncode({'new_name': newName}),
    );

    if (response.statusCode == 200) return true;
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to rename model (${response.statusCode}): ${response.body}');
  }

  /// Register a completed training job under a friendly name.
  /// Calls POST /rename-model with { job_id, model_name }.
  Future<Map<String, dynamic>> saveModelName(String jobId, String modelName) async {
    final headers = await _getAuthHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/rename-model'),
      headers: headers,
      body: jsonEncode({'job_id': jobId, 'model_name': modelName}),
    );

    if (response.statusCode == 200) return jsonDecode(response.body);
    if (response.statusCode == 401) throw Exception('Session expired. Please log in again.');
    throw Exception('Failed to save model name (${response.statusCode}): ${response.body}');
  }
}
