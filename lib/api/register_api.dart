import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:app/core/enums/business_enums.dart';

class RegisterResult {
  final bool success;
  final String? error;

  const RegisterResult.ok() : success = true, error = null;
  const RegisterResult.err(this.error) : success = false;
}

class RegisterApi {
  // Compute URL from environment variables
  String get _baseUrl {
    final baseUrl = kIsWeb || !Platform.isAndroid 
      ? dotenv.get('BACKEND_URL', fallback: 'http://localhost:3000') 
      : dotenv.get('ANDROID_BACKEND_URL', fallback: 'http://10.0.2.2:3000');
    return '$baseUrl/api/auth/register';
  }

  Future<RegisterResult> register({
    required String fullName,
    required String username,
    required String email,
    required String password,
    required String phoneNumber,
    required String businessName,
    required String tradeName,
    required BusinessType businessType,
    required List<String> businessLine,
    required String ownerFirstName,
    required String ownerMiddleName,
    required String ownerLastName,
    required int totalRooms,
    required String permitNumber,
    required String registrationNumber,
    required String street,
    required String barangay,
    required String cityMunicipality,
    required String province,
    required String region,
    required PlatformFile permitFile,
    required PlatformFile validIdFile,
  }) async {
    try {
      // ── 1. Validate inputs ─────────────────────────────────────────────
      final validationError = _validate(
        fullName: fullName,
        username: username,
        email: email,
        phoneNumber: phoneNumber,
        businessName: businessName,
        password: password,
        ownerFirstName: ownerFirstName,
        ownerLastName: ownerLastName,
        businessLine: businessLine,
        totalRooms: totalRooms,
        permitNumber: permitNumber,
        registrationNumber: registrationNumber,
        street: street,
        barangay: barangay,
        cityMunicipality: cityMunicipality,
        province: province,
        region: region,
      );
      if (validationError != null) return RegisterResult.err(validationError);

      // ── 2. Prepare Multipart Request ───────────────────────────────────
      final uri = Uri.parse(_baseUrl);
      final request = http.MultipartRequest('POST', uri);

      // Add API Key from environment
      final apiKey = dotenv.get('API_KEY', fallback: '');
      request.headers['X-API-Key'] = apiKey;

      // Add fields
      request.fields['fullName'] = fullName;
      request.fields['username'] = username.trim().toLowerCase();
      request.fields['email'] = email;
      request.fields['password'] = password;
      request.fields['phoneNumber'] = phoneNumber;
      request.fields['businessName'] = businessName;
      request.fields['tradeName'] = tradeName;
      request.fields['businessType'] = _businessTypeDbValue(businessType);
      request.fields['businessLine'] = jsonEncode(businessLine);
      request.fields['ownerFirstName'] = ownerFirstName;
      request.fields['ownerMiddleName'] = ownerMiddleName;
      request.fields['ownerLastName'] = ownerLastName;
      request.fields['totalRooms'] = totalRooms.toString();
      request.fields['permitNumber'] = permitNumber;
      request.fields['registrationNumber'] = registrationNumber;
      request.fields['street'] = street;
      request.fields['barangay'] = barangay;
      request.fields['cityMunicipality'] = cityMunicipality;
      request.fields['province'] = province;
      request.fields['region'] = region;

      // Add files
      if (kIsWeb) {
        if (permitFile.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'permit_file',
            permitFile.bytes!,
            filename: permitFile.name,
            contentType: _getMediaType(permitFile.name),
          ));
        }
        if (validIdFile.bytes != null) {
          request.files.add(http.MultipartFile.fromBytes(
            'valid_id',
            validIdFile.bytes!,
            filename: validIdFile.name,
            contentType: _getMediaType(validIdFile.name),
          ));
        }
      } else {
        if (permitFile.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'permit_file',
            permitFile.path!,
            contentType: _getMediaType(permitFile.name),
          ));
        }
        if (validIdFile.path != null) {
          request.files.add(await http.MultipartFile.fromPath(
            'valid_id',
            validIdFile.path!,
            contentType: _getMediaType(validIdFile.name),
          ));
        }
      }

      // ── 3. Send Request ───────────────────────────────────────────────
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint('✅ Registration successful via Node.js API');
        return const RegisterResult.ok();
      } else {
        final data = jsonDecode(response.body);
        return RegisterResult.err(data['message'] ?? 'Registration failed.');
      }
    } catch (e) {
      debugPrint('❌ Registration error: $e');
      return RegisterResult.err('An unexpected error occurred: $e');
    }
  }

  MediaType _getMediaType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return MediaType('application', 'pdf');
      case 'png': return MediaType('image', 'png');
      case 'jpg':
      case 'jpeg': return MediaType('image', 'jpeg');
      default: return MediaType('application', 'octet-stream');
    }
  }

  String _businessTypeDbValue(BusinessType businessType) {
    switch (businessType) {
      case BusinessType.corporation:
        return 'corporation';
      case BusinessType.partnership:
        return 'partnership';
      case BusinessType.soleProprietorship:
        return 'sole_proprietorship';
    }
  }

  // ── Field-level validation ───────────────────────────────────────────────

  String? _validate({
    required String fullName,
    required String username,
    required String email,
    required String phoneNumber,
    required String businessName,
    required String password,
    required String ownerFirstName,
    required String ownerLastName,
    required List<String> businessLine,
    required int totalRooms,
    required String permitNumber,
    required String registrationNumber,
    required String street,
    required String barangay,
    required String cityMunicipality,
    required String province,
    required String region,
  }) {
    final usernameRe = RegExp(r'^[a-zA-Z0-9_]{3,20}$');
    final emailRe = RegExp(r'^[\w.+\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    final phoneRe = RegExp(r'^(09|\+639)\d{9}$');
    const allowedBusinessLines = {
      'hotel',
      'resort',
      'motel',
      'pension_inn',
      'youth_hostel',
      'apartment',
      'others',
    };
    final strippedPhone = phoneNumber.replaceAll(RegExp(r'[-\s]'), '');

    if (fullName.trim().isEmpty) return 'Full name is required.';
    if (username.trim().isEmpty) return 'Username is required.';
    if (!usernameRe.hasMatch(username.trim())) {
      return 'Username must be 3-20 characters using letters, numbers, or underscores.';
    }
    if (!emailRe.hasMatch(email.trim())) return 'Enter a valid email address.';
    if (!phoneRe.hasMatch(strippedPhone)) return 'Invalid phone number format.';
    if (businessName.trim().isEmpty) return 'Business name is required.';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters long.';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain at least one uppercase letter.';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain at least one number.';
    }
    if (!RegExp(r"[!@#$%^&*()\-_=+\[\]{};:',.<>?/\\|`~@]").hasMatch(password)) {
      return 'Password must contain at least one special character (e.g. @, #, !).';
    }
    if (businessLine.isEmpty) return 'Select at least one business line.';
    if (businessLine.any((line) => !allowedBusinessLines.contains(line))) {
      return 'Invalid business line selected.';
    }
    if (ownerFirstName.trim().isEmpty) return 'Owner first name is required.';
    if (ownerLastName.trim().isEmpty) return 'Owner last name is required.';
    if (totalRooms <= 0) return 'Total rooms must be at least 1.';
    if (permitNumber.trim().isEmpty) return 'Permit number is required.';
    if (registrationNumber.trim().isEmpty) {
      return 'Registration number is required.';
    }
    if (street.trim().isEmpty) return 'Street is required.';
    if (barangay.trim().isEmpty) return 'Barangay is required.';
    if (cityMunicipality.trim().isEmpty)
      return 'City / Municipality is required.';
    if (province.trim().isEmpty) return 'Province is required.';
    if (region.trim().isEmpty) return 'Region is required.';
    return null;
  }
}

