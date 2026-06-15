import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the in-memory snapshot of the logged-in user's data.
class SessionData {
  final String userId;
  final String fullName;
  final String? username;
  final String email;
  final String phone;
  final String role;
  final String? token;
  final String? password; // NEW: Stored for auto-connect

  /// True when the user logged in without an internet connection.
  /// Certain routes are restricted while this is true.
  final bool isOfflineSession;

  // Business fields (null for admin accounts)
  final String? businessId;
  final String? businessName;
  final String? permitNumber;
  final String? registrationNumber;
  final String? street;
  final int? totalRooms;
  final String? permitFileUrl;
  final String? validIdUrl;
  final String? businessType;
  final String? status;
  final String? remarks;
  final String? region;
  final String? cityMunicipality;
  final String? province;
  final String? barangay;
  final String? tradename;
  final List<String>? businessLine;
  final String? ownerFirstName;
  final String? ownerLastName;
  final String? ownerMiddleName;

  const SessionData({
    required this.userId,
    required this.fullName,
    this.username,
    required this.email,
    required this.phone,
    required this.role,
    this.token,
    this.password,
    this.isOfflineSession = false,
    this.businessId,
    this.businessName,
    this.permitNumber,
    this.registrationNumber,
    this.street,
    this.totalRooms,
    this.permitFileUrl,
    this.validIdUrl,
    this.businessType,
    this.status,
    this.remarks,
    this.region,
    this.cityMunicipality,
    this.province,
    this.barangay,
    this.tradename,
    this.businessLine,
    this.ownerFirstName,
    this.ownerLastName,
    this.ownerMiddleName,
  });

  SessionData copyWith({
    String? userId,
    String? fullName,
    String? username,
    String? email,
    String? phone,
    String? role,
    String? token,
    String? password,
    bool? isOfflineSession,
    String? businessId,
    String? businessName,
    String? permitNumber,
    String? registrationNumber,
    String? street,
    int? totalRooms,
    String? permitFileUrl,
    String? validIdUrl,
    String? businessType,
    String? status,
    String? remarks,
    String? region,
    String? cityMunicipality,
    String? province,
    String? barangay,
    String? tradename,
    List<String>? businessLine,
    String? ownerFirstName,
    String? ownerLastName,
    String? ownerMiddleName,
  }) {
    return SessionData(
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      token: token ?? this.token,
      password: password ?? this.password,
      isOfflineSession: isOfflineSession ?? this.isOfflineSession,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      permitNumber: permitNumber ?? this.permitNumber,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      street: street ?? this.street,
      totalRooms: totalRooms ?? this.totalRooms,
      permitFileUrl: permitFileUrl ?? this.permitFileUrl,
      validIdUrl: validIdUrl ?? this.validIdUrl,
      businessType: businessType ?? this.businessType,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      region: region ?? this.region,
      cityMunicipality: cityMunicipality ?? this.cityMunicipality,
      province: province ?? this.province,
      barangay: barangay ?? this.barangay,
      tradename: tradename ?? this.tradename,
      businessLine: businessLine ?? this.businessLine,
      ownerFirstName: ownerFirstName ?? this.ownerFirstName,
      ownerLastName: ownerLastName ?? this.ownerLastName,
      ownerMiddleName: ownerMiddleName ?? this.ownerMiddleName,
    );
  }

  /// Initials derived from full name, e.g. "Juan Dela Cruz" → "JD"
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String get displayName => fullName;

  /// Concatenated owner name from the business record.
  String get ownerName {
    final parts = <String?>[
      ownerFirstName,
      ownerMiddleName,
      ownerLastName,
    ].where((p) => p != null && p.trim().isNotEmpty).cast<String>();
    return parts.join(' ').trim();
  }
}

/// Persists and retrieves session data via SharedPreferences.
class SessionService extends ChangeNotifier {
  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _kUserId             = 'session_user_id';
  static const _kFullName           = 'session_full_name';
  static const _kUsername           = 'session_username';
  static const _kEmail              = 'session_email';
  static const _kPhone              = 'session_phone';
  static const _kRole               = 'session_role';
  static const _kToken              = 'session_token';
  static const _kPassword           = 'session_password';
  static const _kIsOfflineSession   = 'session_is_offline';
  static const _kBusinessId         = 'session_business_id';
  static const _kBusinessName       = 'session_business_name';
  static const _kPermitNumber       = 'session_permit_number';
  static const _kRegistrationNumber = 'session_registration_number';
  static const _kStreet             = 'session_street';
  static const _kTotalRooms         = 'session_total_rooms';
  static const _kPermitFileUrl      = 'session_permit_file_url';
  static const _kValidIdUrl         = 'session_valid_id_url';
  static const _kBusinessType       = 'session_business_type';
  static const _kStatus             = 'session_status';
  static const _kRemarks            = 'session_remarks';
  static const _kRegion             = 'session_region';
  static const _kCityMunicipality   = 'session_city_municipality';
  static const _kProvince           = 'session_province';
  static const _kBarangay           = 'session_barangay';
  static const _kTradename          = 'session_tradename';
  static const _kBusinessLine       = 'session_business_line';
  static const _kOwnerFirstName     = 'session_owner_first_name';
  static const _kOwnerLastName      = 'session_owner_last_name';
  static const _kOwnerMiddleName    = 'session_owner_middle_name';

  // ── Singleton ─────────────────────────────────────────────────────────────
  SessionService._();
  static final SessionService instance = SessionService._();

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> save(SessionData data) async {
    final prefs = await SharedPreferences.getInstance();
    
    await prefs.setString(_kUserId, data.userId);
    await prefs.setString(_kFullName, data.fullName);
    
    if (data.username != null) {
      await prefs.setString(_kUsername, data.username!);
    } else {
      await prefs.remove(_kUsername);
    }
    
    await prefs.setString(_kEmail, data.email);
    await prefs.setString(_kPhone, data.phone);
    await prefs.setString(_kRole, data.role);
    
    if (data.token != null) {
      await prefs.setString(_kToken, data.token!);
    } else {
      await prefs.remove(_kToken);
    }

    if (data.password != null) {
      await prefs.setString(_kPassword, data.password!);
    } else {
      await prefs.remove(_kPassword);
    }
    
    await prefs.setBool(_kIsOfflineSession, data.isOfflineSession);

    final String? bId = data.businessId;
    if (bId != null) await prefs.setString(_kBusinessId, bId); else await prefs.remove(_kBusinessId);

    final String? bName = data.businessName;
    if (bName != null) await prefs.setString(_kBusinessName, bName); else await prefs.remove(_kBusinessName);

    final String? pNum = data.permitNumber;
    if (pNum != null) await prefs.setString(_kPermitNumber, pNum); else await prefs.remove(_kPermitNumber);

    final String? rNum = data.registrationNumber;
    if (rNum != null) await prefs.setString(_kRegistrationNumber, rNum); else await prefs.remove(_kRegistrationNumber);

    final String? str = data.street;
    if (str != null) await prefs.setString(_kStreet, str); else await prefs.remove(_kStreet);

    final int? tRooms = data.totalRooms;
    if (tRooms != null) await prefs.setInt(_kTotalRooms, tRooms); else await prefs.remove(_kTotalRooms);

    final String? pUrl = data.permitFileUrl;
    if (pUrl != null) await prefs.setString(_kPermitFileUrl, pUrl); else await prefs.remove(_kPermitFileUrl);

    final String? vUrl = data.validIdUrl;
    if (vUrl != null) await prefs.setString(_kValidIdUrl, vUrl); else await prefs.remove(_kValidIdUrl);

    final String? bType = data.businessType;
    if (bType != null) await prefs.setString(_kBusinessType, bType); else await prefs.remove(_kBusinessType);

    final String? stat = data.status;
    if (stat != null) await prefs.setString(_kStatus, stat); else await prefs.remove(_kStatus);

    final String? rem = data.remarks;
    if (rem != null) await prefs.setString(_kRemarks, rem); else await prefs.remove(_kRemarks);

    final String? reg = data.region;
    if (reg != null) await prefs.setString(_kRegion, reg); else await prefs.remove(_kRegion);

    final String? city = data.cityMunicipality;
    if (city != null) await prefs.setString(_kCityMunicipality, city); else await prefs.remove(_kCityMunicipality);

    final String? prov = data.province;
    if (prov != null) await prefs.setString(_kProvince, prov); else await prefs.remove(_kProvince);

    final String? bar = data.barangay;
    if (bar != null) await prefs.setString(_kBarangay, bar); else await prefs.remove(_kBarangay);

    final String? trad = data.tradename;
    if (trad != null) await prefs.setString(_kTradename, trad); else await prefs.remove(_kTradename);

    final List<String>? bLine = data.businessLine;
    if (bLine != null) await prefs.setStringList(_kBusinessLine, bLine); else await prefs.remove(_kBusinessLine);

    final String? oFirst = data.ownerFirstName;
    if (oFirst != null) await prefs.setString(_kOwnerFirstName, oFirst); else await prefs.remove(_kOwnerFirstName);

    final String? oLast = data.ownerLastName;
    if (oLast != null) await prefs.setString(_kOwnerLastName, oLast); else await prefs.remove(_kOwnerLastName);

    final String? oMiddle = data.ownerMiddleName;
    if (oMiddle != null) await prefs.setString(_kOwnerMiddleName, oMiddle); else await prefs.remove(_kOwnerMiddleName);

    _cached = data;
    notifyListeners();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<SessionData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_kUserId);
    if (userId == null) return null;

    return SessionData(
      userId:             userId,
      fullName:           prefs.getString(_kFullName) ?? '',
      username:           prefs.getString(_kUsername),
      email:              prefs.getString(_kEmail) ?? '',
      phone:              prefs.getString(_kPhone) ?? '',
      role:               prefs.getString(_kRole) ?? 'business',
      token:              prefs.getString(_kToken),
      password:           prefs.getString(_kPassword),
      isOfflineSession:   prefs.getBool(_kIsOfflineSession) ?? false,
      businessId:         prefs.getString(_kBusinessId),
      businessName:       prefs.getString(_kBusinessName),
      permitNumber:       prefs.getString(_kPermitNumber),
      registrationNumber: prefs.getString(_kRegistrationNumber),
      street:             prefs.getString(_kStreet),
      totalRooms:         prefs.getInt(_kTotalRooms),
      permitFileUrl:      prefs.getString(_kPermitFileUrl),
      validIdUrl:         prefs.getString(_kValidIdUrl),
      businessType:       prefs.getString(_kBusinessType),
      status:             prefs.getString(_kStatus),
      remarks:            prefs.getString(_kRemarks),
      region:             prefs.getString(_kRegion),
      cityMunicipality:   prefs.getString(_kCityMunicipality),
      province:           prefs.getString(_kProvince),
      barangay:           prefs.getString(_kBarangay),
      tradename:          prefs.getString(_kTradename),
      businessLine:       prefs.getStringList(_kBusinessLine),
      ownerFirstName:     prefs.getString(_kOwnerFirstName),
      ownerLastName:      prefs.getString(_kOwnerLastName),
      ownerMiddleName:    prefs.getString(_kOwnerMiddleName),
    );
  }

  // ── Clear (on logout) ─────────────────────────────────────────────────────
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    // Note: we intentionally do NOT wipe SharedPreferences entirely here
    // so that the SQLite local_profiles data (managed separately) stays intact
    // for future offline logins.
    for (final key in [
      _kUserId, _kFullName, _kUsername, _kEmail, _kPhone, _kRole, _kToken,
      _kIsOfflineSession,
      _kBusinessId, _kBusinessName, _kPermitNumber, _kRegistrationNumber,
      _kStreet, _kTotalRooms, _kPermitFileUrl, _kValidIdUrl, _kBusinessType,
      _kStatus, _kRemarks, _kRegion, _kCityMunicipality, _kProvince,
      _kBarangay, _kTradename, _kBusinessLine, _kOwnerFirstName,
      _kOwnerLastName, _kOwnerMiddleName,
    ]) {
      await prefs.remove(key);
    }
    _cached = null;
    notifyListeners();
  }

  // ── In-memory cache ───────────────────────────────────────────────────────
  SessionData? _cached;
  SessionData? get current => _cached;

  Future<SessionData?> loadAndCache() async {
    _cached = await load();
    notifyListeners();
    return _cached;
  }
}