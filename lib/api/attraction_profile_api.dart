import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'base_api.dart';

enum AttractionType {
  ecotourism,
  naturalAttractions,
  cultural,
  religious,
  historicalHeritageSites,
  agriTourism,
  farmTourismSites;

  String get dbValue => switch (this) {
    AttractionType.ecotourism              => 'ecotourism',
    AttractionType.naturalAttractions      => 'natural_attractions',
    AttractionType.cultural                => 'cultural',
    AttractionType.religious               => 'religious',
    AttractionType.historicalHeritageSites => 'historical_heritage_sites',
    AttractionType.agriTourism             => 'agri_tourism',
    AttractionType.farmTourismSites        => 'farm_tourism_sites',
  };
  String get label => switch (this) {
    AttractionType.ecotourism              => 'Ecotourism',
    AttractionType.naturalAttractions      => 'Natural Attractions',
    AttractionType.cultural                => 'Cultural',
    AttractionType.religious               => 'Religious',
    AttractionType.historicalHeritageSites => 'Historical Heritage Sites',
    AttractionType.agriTourism             => 'Agri-Tourism',
    AttractionType.farmTourismSites        => 'Farm Tourism Sites',
  };
  static AttractionType fromDb(String v) => AttractionType.values.firstWhere(
    (e) => e.dbValue == v, orElse: () => AttractionType.ecotourism);
}

enum AttractionStatus {
  pending, approved, rejected, warning;
  static AttractionStatus fromDb(String v) => AttractionStatus.values.firstWhere(
    (e) => e.name == v, orElse: () => AttractionStatus.pending);
}

class AttractionProfileApi extends BaseApi {
  Future<ProfileModel> fetchProfile() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      return ProfileModel.fromMap(data['user']);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<AttractionProfileModel?> fetchAttraction() async {
    try {
      final response = await get('/api/profile');
      final data = handleResponse(response);
      if (data['attraction'] == null) return null;
      return AttractionProfileModel.fromMap(data['attraction']);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateAccountInfo({
    required String fullName, required String username, required String phone,
  }) async {
    try {
      final response = await put('/api/profile', {
        'full_name': fullName, 'username': username, 'phone': phone,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateAttractionInfo({
    required String attractionName,
    required List<AttractionType> attractionType,
    String? street,
    String? barangay,
  }) async {
    try {
      final response = await put('/api/attraction', {
        'attraction_name': attractionName,
        'attraction_type': attractionType.map((e) => e.dbValue).toList(),
        'street': street,
        'barangay': barangay,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<String> uploadValidId({required PlatformFile validIdFile}) async {
    try {
      final uri = Uri.parse('$baseUrl/api/attraction/upload');
      final request = http.MultipartRequest('POST', uri);

      // Attach auth headers (remove Content-Type — multipart sets its own)
      final h = headers;
      h.remove('Content-Type');
      request.headers.addAll(h);

      if (kIsWeb) {
        if (validIdFile.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'valid_id',
            validIdFile.bytes!,
            filename: validIdFile.name,
            contentType: _getMediaType(validIdFile.name),
          ));
        }
      } else {
        if (validIdFile.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'valid_id',
            validIdFile.path!,
            contentType: _getMediaType(validIdFile.name),
          ));
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['valid_id_url'] as String?) ?? '';
      } else {
        String message = 'Upload failed.';
        try {
          final data = jsonDecode(response.body);
          message = data['message'] ?? message;
        } catch (_) {}
        throw ProfileApiException(message);
      }
    } on ProfileApiException {
      rethrow;
    } catch (e) {
      throw ProfileApiException('Upload failed: $e');
    }
  }

  Future<void> sendPasswordChangeOtp() async {
    try {
      final response = await post('/api/send-email-otp', {});
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> verifyPasswordChangeOtp({required String otp}) async {
    try {
      final profile = await fetchProfile();
      final response = await post('/api/auth/verify-otp', {
        'email': profile.email,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> sendEmailChangeOtp() async {
    try {
      final response = await post('/api/send-email-otp', {});
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> verifyEmailChangeOtp({required String otp}) async {
    try {
      final profile = await fetchProfile();
      final response = await post('/api/auth/verify-otp', {
        'email': profile.email,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updateEmail({required String newEmail, required String otp}) async {
    try {
      final response = await put('/api/update-email', {
        'new_email': newEmail,
        'otp': otp,
      });
      handleResponse(response);
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  Future<void> updatePassword({
    required String newPassword,
    required String confirmPassword,
    String? otp,
    String? oldPassword,
  }) async {
    if (newPassword != confirmPassword) {
      throw const ProfileApiException('Passwords do not match.');
    }
    try {
      if (otp != null) {
        // OTP-based reset (logged in)
        final profile = await fetchProfile();
        final response = await post('/api/auth/reset-password', {
          'email': profile.email,
          'otp': otp,
          'new_password': newPassword,
        });
        handleResponse(response);
      } else if (oldPassword != null) {
        // Traditional change with old password
        final response = await post('/api/change-password', {
          'old_password': oldPassword,
          'new_password': newPassword,
        });
        handleResponse(response);
      } else {
        throw const ProfileApiException('Verification required to change password.');
      }
    } on ApiException catch (e) {
      throw ProfileApiException(e.message);
    }
  }

  MediaType _getMediaType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return MediaType('application', 'pdf');
      case 'png':
        return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      default:
        return MediaType('application', 'octet-stream');
    }
  }
}

class ProfileModel {
  const ProfileModel({
    required this.id, required this.fullName, required this.username,
    required this.email, required this.phone, required this.role,
  });
  final String id, fullName, username, email, phone, role;
  factory ProfileModel.fromMap(Map<String, dynamic> map) => ProfileModel(
    id: map['id'], fullName: map['full_name'], username: map['username'],
    email: map['email'] ?? '', phone: map['phone'] ?? '', role: map['role'],
  );
  ProfileModel copyWith({String? fullName, String? username, String? email, String? phone}) => ProfileModel(
    id: id, fullName: fullName ?? this.fullName, username: username ?? this.username,
    email: email ?? this.email, phone: phone ?? this.phone, role: role,
  );
}

class AttractionProfileModel {
  const AttractionProfileModel({
    required this.id, required this.userId, required this.attractionName,
    required this.attractionType, this.validIdUrl,
    this.barangay, this.street, required this.status, this.remarks,
  });
  final String id, userId, attractionName;
  final List<AttractionType> attractionType;
  final String? validIdUrl, barangay, street, remarks;
  final AttractionStatus status;

  String get typeLabel {
    if (attractionType.isEmpty) return '—';
    return attractionType.map((t) => t.label).join(', ');
  }

  factory AttractionProfileModel.fromMap(Map<String, dynamic> map) {
    final rawTypes = map['attraction_type'];
    final List<String> typeValues = _decodeTypes(rawTypes);

    return AttractionProfileModel(
      id: map['id'], userId: map['user_id'],
      attractionName: map['attraction_name'] ?? '',
      attractionType: typeValues.map((e) => AttractionType.fromDb(e.trim().replaceAll('"', ''))).toList(),
      validIdUrl: map['valid_id_url'],
      barangay: map['barangay'], street: map['street'],
      status: AttractionStatus.fromDb(map['status'] ?? 'pending'),
      remarks: map['remarks'],
    );
  }

  static List<String> _decodeTypes(Object? rawTypes) {
    if (rawTypes is List) {
      return rawTypes.whereType<String>().toList();
    }
    if (rawTypes is String && rawTypes.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTypes);
        return (decoded is List)
            ? decoded.map((e) => e.toString()).toList()
            : <String>[];
      } catch (_) {
        return rawTypes.split(',').map((e) => e.trim()).toList();
      }
    }
    return const <String>[];
  }
}

class ProfileApiException implements Exception {
  final String message;
  const ProfileApiException(this.message);
  @override
  String toString() => message;
}
