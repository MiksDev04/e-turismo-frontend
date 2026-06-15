// // excel_generator_service.dart
// import 'package:excel/excel.dart';
// import 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart';

// class ExcelGeneratorService {
//   static const int _daysInTemplate = 31;

//   static const List<String> _dailyListKeys = [
//     'argentina',
//     'australia',
//     'austria',
//     'bahrain',
//     'bangladesh',
//     'belgium',
//     'brazil',
//     'brunei',
//     'cambodia',
//     'canada',
//     'china',
//     'cis',
//     'colombia',
//     'denmark',
//     'egypt',
//     'filipino_nationality',
//     'finland',
//     'foreign_nationality',
//     'france',
//     'germany',
//     'greece',
//     'guam',
//     'hongkong',
//     'india',
//     'indonesia',
//     'iran',
//     'ireland',
//     'israel',
//     'italy',
//     'japan',
//     'jordan',
//     'korea',
//     'kuwait',
//     'laos',
//     'luxembourg',
//     'malaysia',
//     'mexico',
//     'myanmar',
//     'nauru',
//     'nepal',
//     'netherlands',
//     'new_zealand',
//     'nigeria',
//     'norway',
//     'others_unspecified',
//     'overseas_filipinos',
//     'pakistan',
//     'papua_new_guinea',
//     'peru',
//     'poland',
//     'portugal',
//     'rooms_available',
//     'rooms_occupied',
//     'total_guest_nights',
//     'occupancy_rate',
//     'avg_length_of_stay',
//     'russia',
//     'saudi_arabia',
//     'serbia_montenegro',
//     'singapore',
//     'south_africa',
//     'spain',
//     'sri_lanka',
//     'sweden',
//     'switzerland',
//     'taiwan',
//     'thailand',
//     'uae',
//     'uk',
//     'usa',
//     'venezuela',
//     'vietnam',
//     'male_ph_residents',
//     'female_ph_residents',
//     'male_non_ph_residents',
//     'female_non_ph_residents',
//     'male_overseas_filipinos',
//     'female_overseas_filipinos',
//     'male_others',
//     'female_others',
//   ];

//   static const Map<String, dynamic> _scalarDefaults = {
//     'region': '',
//     'month': '',
//     'year': '',
//     'type_of_accommodation': '',
//     'dot_accreditation_classification': '',
//     'ae_id_code': '',
//     'city_municipality': '',
//     'province': '',
//   };

//   List<int> _asDailyIntList(dynamic value) {
//     if (value is Iterable) {
//       final asInts = value
//           .map((e) => e is num ? e.toInt() : int.tryParse('$e') ?? 0)
//           .toList();
//       if (asInts.length < _daysInTemplate) {
//         asInts.addAll(List<int>.filled(_daysInTemplate - asInts.length, 0));
//       }
//       return asInts.take(_daysInTemplate).toList();
//     }
//     return List<int>.filled(_daysInTemplate, 0);
//   }

//   Map<String, dynamic> _normalizeReportData(Map<String, dynamic> reportData) {
//     final normalized = Map<String, dynamic>.from(reportData);

//     for (final key in _dailyListKeys) {
//       normalized[key] = _asDailyIntList(normalized[key]);
//     }

//     for (final entry in _scalarDefaults.entries) {
//       final value = normalized[entry.key];
//       normalized[entry.key] = value ?? entry.value;
//     }

//     return normalized;
//   }
  
//   /// Generate DAE-1B Excel file with the exact format
//   Future<String> generateDailyAccommodationReport({
//     required Map<String, dynamic> reportData,
//     required String fileName,
//   }) async {
//     final safeData = _normalizeReportData(reportData);

//     // Create a new Excel document
//     var excel = Excel.createExcel();

//     try {
//       // Create the first sheet: "Name of Establishment"
//       var sheet1 = excel['Name of Establishment'];

//       // Set up the worksheet with the exact format
//       _setupWorksheet1(sheet1, safeData);

//       // Create the second sheet: "AE DAE-1B by Country (Sum)"
//       var sheet2 = excel['AE DAE-1B by Country (Sum)'];
//       _setupWorksheet2(sheet2, safeData);

//       // Create the third sheet: "AE DAE-1B (Monthly)"
//       var sheet3 = excel['AE DAE-1B (Monthly)'];
//       _setupWorksheet3(sheet3, safeData);
//     } catch (e) {
//       // Fallback: always produce a valid file instead of failing the export.
//       excel = Excel.createExcel();
//       final fallbackSheet = excel['Report Export'];
//       fallbackSheet.appendRow(['Report Export']);
//       fallbackSheet.appendRow(['Status', 'Fallback generated']);
//       fallbackSheet.appendRow(['Month', '${safeData['month']}']);
//       fallbackSheet.appendRow(['Year', '${safeData['year']}']);
//       fallbackSheet.appendRow(['Notes', 'Template build warning: $e']);
//     }
    
//     // Save the file (platform-specific)
//     List<int>? fileBytes = excel.encode();
//     if (fileBytes == null) return '';

//     final savedPath = await saveFileToDownloads('$fileName.xlsx', fileBytes);
//     return savedPath;
//   }
  
//   void _setupWorksheet1(Sheet sheet, Map<String, dynamic> data) {
//     // Header information
//     sheet.appendRow(['DAE-1B (Manual)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['Region: ${data['region']}']);
//     sheet.appendRow(['____________________________________']);
//     sheet.appendRow(['(${data['month']}, ${data['year']})']);
//     sheet.appendRow([]);
//     sheet.appendRow(['REPORT ON THE REGIONAL DISTRIBUTION OF TRAVELERS']);
//     sheet.appendRow([]);
//     sheet.appendRow(['Type of Accommodation']);
//     sheet.appendRow([data['type_of_accommodation']]);
//     sheet.appendRow([]);
//     sheet.appendRow(['DOT Accreditation Classification: ${data['dot_accreditation_classification']}']);
//     sheet.appendRow([]);
//     sheet.appendRow(['AE ID Code (LGU Assigned): ${data['ae_id_code']}']);
//     sheet.appendRow(['AE ID Code (LGU Assigned): ${data['ae_id_code']}']);
//     sheet.appendRow([]);
//     sheet.appendRow(['City/Municipality: ${data['city_municipality']}']);
//     sheet.appendRow(['Province: ${data['province']}']);
//     sheet.appendRow([]);
    
//     // Country of Residence header row (days 1-31)
//     List<String> headers = ['COUNTRY OF RESIDENCE'];
//     for (int i = 1; i <= 31; i++) {
//       headers.add(i.toString());
//     }
//     headers.add('TOTAL');
//     sheet.appendRow(headers);
//     sheet.appendRow([]);
    
//     // Philippine Residents section
//     sheet.appendRow(['PHILIPPINE RESIDENTS']);
//     sheet.appendRow(['FILIPINO NATIONALITY', ...data['filipino_nationality'], '=SUM(B28:AF28)']);
//     sheet.appendRow(['FOREIGN NATIONALITY', ...data['foreign_nationality'], '=SUM(B29:AF29)']);
    
//     List<dynamic> totalRow = ['TOTAL PHILIPPINE RESIDENTS'];
//     for (int i = 0; i < 31; i++) {
//       int filVal = data['filipino_nationality'][i] ?? 0;
//       int forVal = data['foreign_nationality'][i] ?? 0;
//       totalRow.add(filVal + forVal);
//     }
//     totalRow.add('=SUM(B30:AF30)');
//     sheet.appendRow(totalRow);
//     sheet.appendRow([]);
    
//     // NON-PHILIPPINE RESIDENTS
//     sheet.appendRow(['NON-PHILIPPINE RESIDENTS']);
//     sheet.appendRow([]);
    
//     // ASIA - ASEAN
//     sheet.appendRow(['ASIA']);
//     sheet.appendRow(['ASEAN']);
//     _addCountryRow(sheet, 'BRUNEI', data['brunei']);
//     _addCountryRow(sheet, 'CAMBODIA', data['cambodia']);
//     _addCountryRow(sheet, 'INDONESIA', data['indonesia']);
//     _addCountryRow(sheet, 'LAOS', data['laos']);
//     _addCountryRow(sheet, 'MALAYSIA', data['malaysia']);
//     _addCountryRow(sheet, 'MYANMAR', data['myanmar']);
//     _addCountryRow(sheet, 'SINGAPORE', data['singapore']);
//     _addCountryRow(sheet, 'THAILAND', data['thailand']);
//     _addCountryRow(sheet, 'VIETNAM', data['vietnam']);
    
//     // ASEAN Sub-total
//     List<dynamic> aseanSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['brunei'][i] ?? 0) + (data['cambodia'][i] ?? 0) +
//           (data['indonesia'][i] ?? 0) + (data['laos'][i] ?? 0) +
//           (data['malaysia'][i] ?? 0) + (data['myanmar'][i] ?? 0) +
//           (data['singapore'][i] ?? 0) + (data['thailand'][i] ?? 0) +
//           (data['vietnam'][i] ?? 0);
//       aseanSubtotal.add(sum);
//     }
//     aseanSubtotal.add('=SUM(B45:AF45)');
//     sheet.appendRow(aseanSubtotal);
//     sheet.appendRow([]);
    
//     // East Asia
//     sheet.appendRow(['EAST ASIA']);
//     _addCountryRow(sheet, 'CHINA', data['china']);
//     _addCountryRow(sheet, 'HONGKONG', data['hongkong']);
//     _addCountryRow(sheet, 'JAPAN', data['japan']);
//     _addCountryRow(sheet, 'KOREA', data['korea']);
//     _addCountryRow(sheet, 'TAIWAN', data['taiwan']);
    
//     // East Asia Sub-total
//     List<dynamic> eastAsiaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['china'][i] ?? 0) + (data['hongkong'][i] ?? 0) +
//           (data['japan'][i] ?? 0) + (data['korea'][i] ?? 0) +
//           (data['taiwan'][i] ?? 0);
//       eastAsiaSubtotal.add(sum);
//     }
//     eastAsiaSubtotal.add('=SUM(B53:AF53)');
//     sheet.appendRow(eastAsiaSubtotal);
//     sheet.appendRow([]);
    
//     // South Asia
//     sheet.appendRow(['SOUTH ASIA']);
//     _addCountryRow(sheet, 'BANGLADESH', data['bangladesh']);
//     _addCountryRow(sheet, 'INDIA', data['india']);
//     _addCountryRow(sheet, 'IRAN', data['iran']);
//     _addCountryRow(sheet, 'NEPAL', data['nepal']);
//     _addCountryRow(sheet, 'PAKISTAN', data['pakistan']);
//     _addCountryRow(sheet, 'SRI LANKA', data['sri_lanka']);
    
//     List<dynamic> southAsiaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['bangladesh'][i] ?? 0) + (data['india'][i] ?? 0) +
//           (data['iran'][i] ?? 0) + (data['nepal'][i] ?? 0) +
//           (data['pakistan'][i] ?? 0) + (data['sri_lanka'][i] ?? 0);
//       southAsiaSubtotal.add(sum);
//     }
//     southAsiaSubtotal.add('=SUM(B62:AF62)');
//     sheet.appendRow(southAsiaSubtotal);
//     sheet.appendRow([]);
    
//     // Middle East
//     sheet.appendRow(['MIDDLE EAST']);
//     _addCountryRow(sheet, 'BAHRAIN', data['bahrain']);
//     _addCountryRow(sheet, 'EGYPT', data['egypt']);
//     _addCountryRow(sheet, 'ISRAEL', data['israel']);
//     _addCountryRow(sheet, 'JORDAN', data['jordan']);
//     _addCountryRow(sheet, 'KUWAIT', data['kuwait']);
//     _addCountryRow(sheet, 'SAUDI ARABIA', data['saudi_arabia']);
//     _addCountryRow(sheet, 'UNITED ARAB EMIRATES', data['uae']);
    
//     List<dynamic> middleEastSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['bahrain'][i] ?? 0) + (data['egypt'][i] ?? 0) +
//           (data['israel'][i] ?? 0) + (data['jordan'][i] ?? 0) +
//           (data['kuwait'][i] ?? 0) + (data['saudi_arabia'][i] ?? 0) +
//           (data['uae'][i] ?? 0);
//       middleEastSubtotal.add(sum);
//     }
//     middleEastSubtotal.add('=SUM(B73:AF73)');
//     sheet.appendRow(middleEastSubtotal);
//     sheet.appendRow([]);
    
//     // Americas
//     sheet.appendRow(['AMERICA']);
//     sheet.appendRow(['NORTH AMERICA']);
//     _addCountryRow(sheet, 'CANADA', data['canada']);
//     _addCountryRow(sheet, 'MEXICO', data['mexico']);
//     _addCountryRow(sheet, 'USA', data['usa']);
    
//     List<dynamic> northAmericaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['canada'][i] ?? 0) + (data['mexico'][i] ?? 0) +
//           (data['usa'][i] ?? 0);
//       northAmericaSubtotal.add(sum);
//     }
//     northAmericaSubtotal.add('=SUM(B80:AF80)');
//     sheet.appendRow(northAmericaSubtotal);
//     sheet.appendRow([]);
    
//     sheet.appendRow(['SOUTH AMERICA']);
//     _addCountryRow(sheet, 'ARGENTINA', data['argentina']);
//     _addCountryRow(sheet, 'BRAZIL', data['brazil']);
//     _addCountryRow(sheet, 'COLOMBIA', data['colombia']);
//     _addCountryRow(sheet, 'PERU', data['peru']);
//     _addCountryRow(sheet, 'VENEZUELA', data['venezuela']);
    
//     List<dynamic> southAmericaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['argentina'][i] ?? 0) + (data['brazil'][i] ?? 0) +
//           (data['colombia'][i] ?? 0) + (data['peru'][i] ?? 0) +
//           (data['venezuela'][i] ?? 0);
//       southAmericaSubtotal.add(sum);
//     }
//     southAmericaSubtotal.add('=SUM(B88:AF88)');
//     sheet.appendRow(southAmericaSubtotal);
//     sheet.appendRow([]);
    
//     // Europe sections
//     sheet.appendRow(['EUROPE']);
//     sheet.appendRow(['WESTERN EUROPE']);
//     _addCountryRow(sheet, 'AUSTRIA', data['austria']);
//     _addCountryRow(sheet, 'BELGIUM', data['belgium']);
//     _addCountryRow(sheet, 'FRANCE', data['france']);
//     _addCountryRow(sheet, 'GERMANY', data['germany']);
//     _addCountryRow(sheet, 'LUXEMBOURG', data['luxembourg']);
//     _addCountryRow(sheet, 'NETHERLANDS', data['netherlands']);
//     _addCountryRow(sheet, 'SWITZERLAND', data['switzerland']);
    
//     List<dynamic> westernEuropeSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['austria'][i] ?? 0) + (data['belgium'][i] ?? 0) +
//           (data['france'][i] ?? 0) + (data['germany'][i] ?? 0) +
//           (data['luxembourg'][i] ?? 0) + (data['netherlands'][i] ?? 0) +
//           (data['switzerland'][i] ?? 0);
//       westernEuropeSubtotal.add(sum);
//     }
//     westernEuropeSubtotal.add('=SUM(B99:AF99)');
//     sheet.appendRow(westernEuropeSubtotal);
//     sheet.appendRow([]);
    
//     sheet.appendRow(['NORTHERN EUROPE']);
//     _addCountryRow(sheet, 'DENMARK', data['denmark']);
//     _addCountryRow(sheet, 'FINLAND', data['finland']);
//     _addCountryRow(sheet, 'IRELAND', data['ireland']);
//     _addCountryRow(sheet, 'NORWAY', data['norway']);
//     _addCountryRow(sheet, 'SWEDEN', data['sweden']);
//     _addCountryRow(sheet, 'UNITED KINGDOM', data['uk']);
    
//     List<dynamic> northernEuropeSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['denmark'][i] ?? 0) + (data['finland'][i] ?? 0) +
//           (data['ireland'][i] ?? 0) + (data['norway'][i] ?? 0) +
//           (data['sweden'][i] ?? 0) + (data['uk'][i] ?? 0);
//       northernEuropeSubtotal.add(sum);
//     }
//     northernEuropeSubtotal.add('=SUM(B108:AF108)');
//     sheet.appendRow(northernEuropeSubtotal);
//     sheet.appendRow([]);
    
//     sheet.appendRow(['SOUTHERN EUROPE']);
//     _addCountryRow(sheet, 'GREECE', data['greece']);
//     _addCountryRow(sheet, 'ITALY', data['italy']);
//     _addCountryRow(sheet, 'PORTUGAL', data['portugal']);
//     _addCountryRow(sheet, 'SPAIN', data['spain']);
//     _addCountryRow(sheet, 'UNION OF SERBIA AND MONTENEGRO', data['serbia_montenegro']);
    
//     List<dynamic> southernEuropeSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['greece'][i] ?? 0) + (data['italy'][i] ?? 0) +
//           (data['portugal'][i] ?? 0) + (data['spain'][i] ?? 0) +
//           (data['serbia_montenegro'][i] ?? 0);
//       southernEuropeSubtotal.add(sum);
//     }
//     southernEuropeSubtotal.add('=SUM(B116:AF116)');
//     sheet.appendRow(southernEuropeSubtotal);
//     sheet.appendRow([]);
    
//     sheet.appendRow(['EASTERN EUROPE']);
//     _addCountryRow(sheet, 'COMMONWEALTH OF INDEPENDENT STATES', data['cis']);
//     _addCountryRow(sheet, 'POLAND', data['poland']);
//     _addCountryRow(sheet, 'RUSSIA', data['russia']);
    
//     List<dynamic> easternEuropeSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['cis'][i] ?? 0) + (data['poland'][i] ?? 0) +
//           (data['russia'][i] ?? 0);
//       easternEuropeSubtotal.add(sum);
//     }
//     easternEuropeSubtotal.add('=SUM(B122:AF122)');
//     sheet.appendRow(easternEuropeSubtotal);
//     sheet.appendRow([]);
    
//     // Australasia/Pacific
//     sheet.appendRow(['AUSTRALASIA/PACIFIC']);
//     _addCountryRow(sheet, 'AUSTRALIA', data['australia']);
//     _addCountryRow(sheet, 'GUAM', data['guam']);
//     _addCountryRow(sheet, 'NAURU', data['nauru']);
//     _addCountryRow(sheet, 'NEW ZEALAND', data['new_zealand']);
//     _addCountryRow(sheet, 'PAPUA NEW GUINEA', data['papua_new_guinea']);
    
//     List<dynamic> australasiaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['australia'][i] ?? 0) + (data['guam'][i] ?? 0) +
//           (data['nauru'][i] ?? 0) + (data['new_zealand'][i] ?? 0) +
//           (data['papua_new_guinea'][i] ?? 0);
//       australasiaSubtotal.add(sum);
//     }
//     australasiaSubtotal.add('=SUM(B131:AF131)');
//     sheet.appendRow(australasiaSubtotal);
//     sheet.appendRow([]);
    
//     // Africa
//     sheet.appendRow(['AFRICA']);
//     _addCountryRow(sheet, 'NIGERIA', data['nigeria']);
//     _addCountryRow(sheet, 'SOUTH AFRICA', data['south_africa']);
    
//     List<dynamic> africaSubtotal = ['SUB-TOTAL'];
//     for (int i = 0; i < 31; i++) {
//       int sum = (data['nigeria'][i] ?? 0) + (data['south_africa'][i] ?? 0);
//       africaSubtotal.add(sum);
//     }
//     africaSubtotal.add('=SUM(B137:AF137)');
//     sheet.appendRow(africaSubtotal);
//     sheet.appendRow([]);
    
//     // Others and Unspecified
//     sheet.appendRow(['OTHERS AND UNSPECIFIED']);
//     _addCountryRow(sheet, 'NON-PHILIPPINE RESIDENCES', data['others_unspecified']);
//     sheet.appendRow([]);
    
//     // Calculate non-philippine residents total
//     List<dynamic> nonPhTotal = ['TOTAL NON-PHILIPPINE RESIDENTS'];
//     // This is a simplified version - full formula would sum multiple subtotals
//     for (int i = 0; i < 31; i++) {
//       nonPhTotal.add((data['others_unspecified'][i] ?? 0) + 
//           (data['nigeria'][i] ?? 0) + (data['south_africa'][i] ?? 0) +
//           (data['australia'][i] ?? 0) + (data['guam'][i] ?? 0) +
//           (data['nauru'][i] ?? 0) + (data['new_zealand'][i] ?? 0) +
//           (data['papua_new_guinea'][i] ?? 0));
//     }
//     nonPhTotal.add('=SUM(B141:AF141)');
//     sheet.appendRow(nonPhTotal);
//     sheet.appendRow([]);
    
//     // Overseas Filipinos
//     _addCountryRow(sheet, 'OVERSEAS FILIPINOS*', data['overseas_filipinos']);
//     sheet.appendRow([]);
    
//     // Grand Total
//     List<dynamic> grandTotal = ['GRAND TOTAL GUEST ARRIVALS'];
//     for (int i = 0; i < 31; i++) {
//       int total = (data['overseas_filipinos'][i] ?? 0) + 
//           (data['others_unspecified'][i] ?? 0) +
//           ((data['filipino_nationality'][i] ?? 0) + (data['foreign_nationality'][i] ?? 0));
//       grandTotal.add(total);
//     }
//     grandTotal.add('=SUM(B145:AF145)');
//     sheet.appendRow(grandTotal);
    
//     // Summary rows
//     _addSummaryRows(sheet, data);
    
//     // Part II: Other Indicators
//     sheet.appendRow([]);
//     sheet.appendRow(['PART II.  Other Indicators']);
//     sheet.appendRow([]);
//     sheet.appendRow(['A. DAE2:']);
//     _addDataRow(sheet, '1. Rooms Occupied', data['rooms_occupied']);
//     _addDataRow(sheet, '2. Rooms available for the month', data['rooms_available']);
//     _addDataRow(sheet, '3. Total Guest nights', data['total_guest_nights']);
//     sheet.appendRow(['Alternative Submission']);
//     _addDataRow(sheet, '1. Average Monthly Occupancy Rate', data['occupancy_rate']);
//     _addDataRow(sheet, '2. Average Length of Stay (in Nights)', data['avg_length_of_stay']);
    
//     sheet.appendRow(['B. VOLUME PER SEX']);
//     sheet.appendRow(['1. Male']);
//     _addDataRow(sheet, 'a. Philippine Residents', data['male_ph_residents']);
//     _addDataRow(sheet, 'b. Non-Philippine/Foreign Residents (including unspecified)', data['male_non_ph_residents']);
//     _addDataRow(sheet, 'c. Overseas Filipinos', data['male_overseas_filipinos']);
//     _addDataRow(sheet, 'd. Others/Unspecified Guest', data['male_others']);
//     _addTotalRow(sheet, 'x. Total', data['male_ph_residents'], data['male_non_ph_residents'], 
//         data['male_overseas_filipinos'], data['male_others']);
    
//     sheet.appendRow(['2. Female']);
//     _addDataRow(sheet, 'a. Philippine Residents', data['female_ph_residents']);
//     _addDataRow(sheet, 'b. Non-Philippine/Foreign Residents (including unspecified)', data['female_non_ph_residents']);
//     _addDataRow(sheet, 'c. Overseas Filipinos', data['female_overseas_filipinos']);
//     _addDataRow(sheet, 'd. Others/Unspecified Guest', data['female_others']);
//     _addTotalRow(sheet, 'x. Total', data['female_ph_residents'], data['female_non_ph_residents'],
//         data['female_overseas_filipinos'], data['female_others']);
    
//     // Signature section
//     sheet.appendRow([]);
//     sheet.appendRow(['Prepared by:            ____________________________________                         ________________________________________                         ____________________________________']);
//     sheet.appendRow(['Signature over Printed Name                                                     Position/Designation']);
//   }
  
//   void _addSummaryRows(Sheet sheet, Map<String, dynamic> data) {
//     List<dynamic> phResidentsTotal = ['Total Philippine Residents'];
//     for (int i = 0; i < 31; i++) {
//       phResidentsTotal.add((data['filipino_nationality'][i] ?? 0) + (data['foreign_nationality'][i] ?? 0));
//     }
//     phResidentsTotal.add('=SUM(B147:AF147)');
//     sheet.appendRow(phResidentsTotal);
    
//     List<dynamic> nonPhResidentsTotal = ['Total Non-Philippine Residents'];
//     for (int i = 0; i < 31; i++) {
//       nonPhResidentsTotal.add(data['others_unspecified'][i] ?? 0);
//     }
//     nonPhResidentsTotal.add('=SUM(B148:AF148)');
//     sheet.appendRow(nonPhResidentsTotal);
    
//     List<dynamic> overseasFilipinosTotal = ['Total Overseas Filipinos'];
//     for (int i = 0; i < 31; i++) {
//       overseasFilipinosTotal.add(data['overseas_filipinos'][i] ?? 0);
//     }
//     overseasFilipinosTotal.add('=SUM(B149:AF149)');
//     sheet.appendRow(overseasFilipinosTotal);
    
//     List<dynamic> unspecifiedTotal = ['Total Guest with Unspecified Residence'];
//     for (int i = 0; i < 31; i++) {
//       unspecifiedTotal.add(0);
//     }
//     unspecifiedTotal.add('=SUM(B150:AF150)');
//     sheet.appendRow(unspecifiedTotal);
//   }
  
//   void _addCountryRow(Sheet sheet, String country, dynamic data) {
//     final values = _asDailyIntList(data);
//     List<dynamic> row = [country];
//     row.addAll(values);
//     row.add('=SUM(B${sheet.rows.length + 1}:AF${sheet.rows.length + 1})');
//     sheet.appendRow(row);
//   }
  
//   void _addDataRow(Sheet sheet, String label, dynamic data) {
//     final values = _asDailyIntList(data);
//     List<dynamic> row = [label];
//     row.addAll(values);
//     row.add('=SUM(B${sheet.rows.length + 1}:AF${sheet.rows.length + 1})');
//     sheet.appendRow(row);
//   }
  
//   void _addTotalRow(
//     Sheet sheet,
//     String label,
//     dynamic data1,
//     dynamic data2,
//     dynamic data3,
//     dynamic data4,
//   ) {
//     final values1 = _asDailyIntList(data1);
//     final values2 = _asDailyIntList(data2);
//     final values3 = _asDailyIntList(data3);
//     final values4 = _asDailyIntList(data4);
//     List<dynamic> row = [label];
//     for (int i = 0; i < 31; i++) {
//       row.add(values1[i] + values2[i] + values3[i] + values4[i]);
//     }
//     row.add('=SUM(B${sheet.rows.length + 1}:AF${sheet.rows.length + 1})');
//     sheet.appendRow(row);
//   }

//   int _sumList(dynamic maybeList) {
//     if (maybeList is Iterable) {
//       return maybeList.fold<int>(0, (prev, el) {
//         if (el is num) return prev + el.toInt();
//         return prev + (int.tryParse('$el') ?? 0);
//       });
//     }
//     return 0;
//   }
  
//   void _setupWorksheet2(Sheet sheet, Map<String, dynamic> data) {
//     sheet.appendRow(['DAE-1B(Manual-Summary)']);
//     sheet.appendRow([]);
//     sheet.appendRow([]);
//     sheet.appendRow([]);
//     sheet.appendRow(['(Month, Year)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['REPORT ON THE REGIONAL DISTRIBUTION OF TRAVELERS']);
//     sheet.appendRow([]);
//     sheet.appendRow(['Type of Accommodation']);
//     sheet.appendRow([data['type_of_accommodation']]);
//     sheet.appendRow([]);
//     sheet.appendRow(['DOT Accreditation Classification: ${data['dot_accreditation_classification']}']);
//     sheet.appendRow([]);
//     sheet.appendRow(['AE ID Code (LGU Assigned): ${data['ae_id_code']}']);
//     sheet.appendRow([data['ae_id_code']]);
//     sheet.appendRow([]);
//     sheet.appendRow(['City/Municipality: ${data['city_municipality']}']);
//     sheet.appendRow(['Province: ${data['province']}']);
//     sheet.appendRow([]);
//     sheet.appendRow(['COUNTRY OF RESIDENCE', 'TOTAL']);
//     sheet.appendRow([]);
//     sheet.appendRow(['PHILIPPINE RESIDENTS']);
//     sheet.appendRow(['FILIPINO NATIONALITY', _sumList(data['filipino_nationality'])]);
//     sheet.appendRow(['FOREIGN NATIONALITY', _sumList(data['foreign_nationality'])]);
//     sheet.appendRow(['TOTAL PHILIPPINE RESIDENTS', _sumList(data['filipino_nationality']) + _sumList(data['foreign_nationality'])]);
//     sheet.appendRow([]);
//     sheet.appendRow(['NON-PHILIPPINE RESIDENTS']);
//     sheet.appendRow([]);
//     sheet.appendRow(['ASIA']);
//     sheet.appendRow(['ASEAN']);
//     sheet.appendRow(['BRUNEI', _sumList(data['brunei'])]);
//     sheet.appendRow(['CAMBODIA', _sumList(data['cambodia'])]);
//     sheet.appendRow(['INDONESIA', _sumList(data['indonesia'])]);
//     sheet.appendRow(['LAOS', _sumList(data['laos'])]);
//     sheet.appendRow(['MALAYSIA', _sumList(data['malaysia'])]);
//     sheet.appendRow(['MYANMAR', _sumList(data['myanmar'])]);
//     sheet.appendRow(['SINGAPORE', _sumList(data['singapore'])]);
//     sheet.appendRow(['THAILAND', _sumList(data['thailand'])]);
//     sheet.appendRow(['VIETNAM', _sumList(data['vietnam'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B13:B21)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['EAST ASIA']);
//     sheet.appendRow(['CHINA', _sumList(data['china'])]);
//     sheet.appendRow(['HONGKONG', _sumList(data['hongkong'])]);
//     sheet.appendRow(['JAPAN', _sumList(data['japan'])]);
//     sheet.appendRow(['KOREA', _sumList(data['korea'])]);
//     sheet.appendRow(['TAIWAN', _sumList(data['taiwan'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B25:B29)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['SOUTH ASIA']);
//     sheet.appendRow(['BANGLADESH', _sumList(data['bangladesh'])]);
//     sheet.appendRow(['INDIA', _sumList(data['india'])]);
//     sheet.appendRow(['IRAN', _sumList(data['iran'])]);
//     sheet.appendRow(['NEPAL', _sumList(data['nepal'])]);
//     sheet.appendRow(['PAKISTAN', _sumList(data['pakistan'])]);
//     sheet.appendRow(['SRI LANKA', _sumList(data['sri_lanka'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B33:B38)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['MIDDLE EAST']);
//     sheet.appendRow(['BAHRAIN', _sumList(data['bahrain'])]);
//     sheet.appendRow(['EGYPT', _sumList(data['egypt'])]);
//     sheet.appendRow(['ISRAEL', _sumList(data['israel'])]);
//     sheet.appendRow(['JORDAN', _sumList(data['jordan'])]);
//     sheet.appendRow(['KUWAIT', _sumList(data['kuwait'])]);
//     sheet.appendRow(['SAUDI ARABIA', _sumList(data['saudi_arabia'])]);
//     sheet.appendRow(['UNITED ARAB EMIRATES', _sumList(data['uae'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B42:B48)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['COUNTRY OF RESIDENCE', 'TOTAL']);
//     sheet.appendRow(['AMERICA']);
//     sheet.appendRow(['NORTH AMERICA']);
//     sheet.appendRow(['CANADA', _sumList(data['canada'])]);
//     sheet.appendRow(['MEXICO', _sumList(data['mexico'])]);
//     sheet.appendRow(['USA', _sumList(data['usa'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B54:B56)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['SOUTH AMERICA']);
//     sheet.appendRow(['ARGENTINA', _sumList(data['argentina'])]);
//     sheet.appendRow(['BRAZIL', _sumList(data['brazil'])]);
//     sheet.appendRow(['COLOMBIA', _sumList(data['colombia'])]);
//     sheet.appendRow(['PERU', _sumList(data['peru'])]);
//     sheet.appendRow(['VENEZUELA', _sumList(data['venezuela'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B60:B64)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['EUROPE']);
//     sheet.appendRow(['WESTERN EUROPE']);
//     sheet.appendRow(['AUSTRIA', _sumList(data['austria'])]);
//     sheet.appendRow(['BELGIUM', _sumList(data['belgium'])]);
//     sheet.appendRow(['FRANCE', _sumList(data['france'])]);
//     sheet.appendRow(['GERMANY', _sumList(data['germany'])]);
//     sheet.appendRow(['LUXEMBOURG', _sumList(data['luxembourg'])]);
//     sheet.appendRow(['NETHERLANDS', _sumList(data['netherlands'])]);
//     sheet.appendRow(['SWITZERLAND', _sumList(data['switzerland'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B69:B75)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['NORTHERN EUROPE']);
//     sheet.appendRow(['DENMARK', _sumList(data['denmark'])]);
//     sheet.appendRow(['FINLAND', _sumList(data['finland'])]);
//     sheet.appendRow(['IRELAND', _sumList(data['ireland'])]);
//     sheet.appendRow(['NORWAY', _sumList(data['norway'])]);
//     sheet.appendRow(['SWEDEN', _sumList(data['sweden'])]);
//     sheet.appendRow(['UNITED KINGDOM', _sumList(data['uk'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B79:B84)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['SOUTHERN EUROPE']);
//     sheet.appendRow(['GREECE', _sumList(data['greece'])]);
//     sheet.appendRow(['ITALY', _sumList(data['italy'])]);
//     sheet.appendRow(['PORTUGAL', _sumList(data['portugal'])]);
//     sheet.appendRow(['SPAIN', _sumList(data['spain'])]);
//     sheet.appendRow(['UNION OF SERBIA AND MONTENEGRO', _sumList(data['serbia_montenegro'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B88:B92)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['EASTERN EUROPE']);
//     sheet.appendRow(['COMMONWEALTH OF INDEPENDENT STATES', _sumList(data['cis'])]);
//     sheet.appendRow(['POLAND', _sumList(data['poland'])]);
//     sheet.appendRow(['RUSSIA', _sumList(data['russia'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B96:B98)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['AUSTRALASIA/PACIFIC']);
//     sheet.appendRow(['AUSTRALIA', _sumList(data['australia'])]);
//     sheet.appendRow(['GUAM', _sumList(data['guam'])]);
//     sheet.appendRow(['NAURU', _sumList(data['nauru'])]);
//     sheet.appendRow(['NEW ZEALAND', _sumList(data['new_zealand'])]);
//     sheet.appendRow(['PAPUA NEW GUINEA', _sumList(data['papua_new_guinea'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B102:B106)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['COUNTRY OF RESIDENCE', 'TOTAL']);
//     sheet.appendRow([]);
//     sheet.appendRow(['AFRICA']);
//     sheet.appendRow(['NIGERIA', _sumList(data['nigeria'])]);
//     sheet.appendRow(['SOUTH AFRICA', _sumList(data['south_africa'])]);
//     sheet.appendRow(['SUB-TOTAL', '=SUM(B112:B113)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['OTHERS AND UNSPECIFIED']);
//     sheet.appendRow(['NON-PHILIPPINE RESIDENCES', _sumList(data['others_unspecified'])]);
//     sheet.appendRow([]);
//     sheet.appendRow(['TOTAL NON-PHILIPPINE RESIDENTS', '=SUM(B115,B111,B107,B99,B93,B87,B79,B71,B63,B55,B45,B41,B28)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['OVERSEAS FILIPINOS*', _sumList(data['overseas_filipinos'])]);
//     sheet.appendRow([]);
//     sheet.appendRow(['GRAND TOTAL GUEST ARRIVALS', '=SUM(B120,B118,B15)']);
//     sheet.appendRow(['Total Philippine Residents', '=B15']);
//     sheet.appendRow(['Total Non-Philippine Residents', '=B118']);
//     sheet.appendRow(['Total Overseas Filipinos', '=B120']);
//     sheet.appendRow(['Total Guest with Unspecified Residence', '=B115']);
//   }
  
//   void _setupWorksheet3(Sheet sheet, Map<String, dynamic> data) {
//     sheet.appendRow(['DAE-1B(Manual-Summary)']);
//     sheet.appendRow([]);
//     sheet.appendRow([]);
//     sheet.appendRow([]);
//     sheet.appendRow(['(Month, Year)']);
//     sheet.appendRow([]);
//     sheet.appendRow(['REPORT ON THE REGIONAL DISTRIBUTION OF TRAVELERS']);
//     sheet.appendRow([]);
//     sheet.appendRow(['Type of Accommodation']);
//     sheet.appendRow([data['type_of_accommodation']]);
//     sheet.appendRow([]);
//     sheet.appendRow(['DOT Accreditation Classification: ${data['dot_accreditation_classification']}']);
//     sheet.appendRow([]);
//     sheet.appendRow(['AE ID Code (LGU Assigned): ${data['ae_id_code']}']);
//     sheet.appendRow([data['ae_id_code']]);
//     sheet.appendRow([]);
//     sheet.appendRow(['City/Municipality: ${data['city_municipality']}']);
//     sheet.appendRow(['Province: ${data['province']}']);
//     sheet.appendRow([]);
    
//     // Monthly summary headers
//     List<String> months = ['COUNTRY OF RESIDENCE', 'JANUARY', 'FEBRUARY', 'MARCH', 'APRIL', 'MAY', 'JUNE', 
//                            'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER', 'NOVEMBER', 'DECEMBER', 'TOTAL'];
//     sheet.appendRow(months);
//     sheet.appendRow([]);
    
//     // Philippine Residents monthly
//     sheet.appendRow(['PHILIPPINE RESIDENTS']);
//     sheet.appendRow(['FILIPINO NATIONALITY']);
//     sheet.appendRow(['FOREIGN NATIONALITY']);
//     List<dynamic> totalPhRow = ['TOTAL PHILIPPINE RESIDENTS'];
//     months.skip(1).take(12).forEach((_) => totalPhRow.add(''));
//     totalPhRow.add('=SUM(B30:M30)');
//     sheet.appendRow(totalPhRow);
    
//     // Sample monthly values for demonstration
//     sheet.appendRow(['NON-PHILIPPINE RESIDENTS']);
//     sheet.appendRow([]);
//     sheet.appendRow(['ASIA']);
//     sheet.appendRow(['ASEAN']);
//     sheet.appendRow(['BRUNEI']);
//     sheet.appendRow(['CAMBODIA']);
//     sheet.appendRow(['INDONESIA']);
//     sheet.appendRow(['LAOS']);
//     sheet.appendRow(['MALAYSIA']);
//     sheet.appendRow(['MYANMAR']);
//     sheet.appendRow(['SINGAPORE']);
//     sheet.appendRow(['THAILAND']);
//     sheet.appendRow(['VIETNAM']);
    
//     List<dynamic> aseanSubtotal = ['SUB-TOTAL'];
//     months.skip(1).take(12).forEach((_) => aseanSubtotal.add(''));
//     aseanSubtotal.add('=SUM(B45:M45)');
//     sheet.appendRow(aseanSubtotal);
//     sheet.appendRow([]);
    
//     // Continue with other regions similarly
//     sheet.appendRow(['EAST ASIA']);
//     sheet.appendRow(['CHINA']);
//     sheet.appendRow(['HONGKONG']);
//     sheet.appendRow(['JAPAN']);
//     sheet.appendRow(['KOREA']);
//     sheet.appendRow(['TAIWAN']);
    
//     List<dynamic> eastAsiaSubtotal = ['SUB-TOTAL'];
//     months.skip(1).take(12).forEach((_) => eastAsiaSubtotal.add(''));
//     eastAsiaSubtotal.add('=SUM(B53:M53)');
//     sheet.appendRow(eastAsiaSubtotal);
    
//     // Final summary rows
//     sheet.appendRow([]);
//     sheet.appendRow(['GRAND TOTAL GUEST ARRIVALS']);
//     sheet.appendRow(['Total Philippine Residents']);
//     sheet.appendRow(['Total Non-Philippine Residents']);
//     sheet.appendRow(['Total Overseas Filipinos']);
//     sheet.appendRow(['Total Guest with Unspecified Residence']);
    
//     sheet.appendRow([]);
//     sheet.appendRow(['PART II.  Other Indicators']);
//     sheet.appendRow([]);
//     sheet.appendRow(['A. DAE2:']);
//     sheet.appendRow(['1. Rooms Occupied']);
//     sheet.appendRow(['2. Rooms available for the month']);
//     sheet.appendRow(['3. Total Guest nights']);
//     sheet.appendRow(['Alternative Submission']);
//     sheet.appendRow(['1. Average Monthly Occupancy Rate']);
//     sheet.appendRow(['2. Average Length of Stay (in Nights)']);
//     sheet.appendRow(['B. VOLUME PER SEX']);
//     sheet.appendRow(['1. Male']);
//     sheet.appendRow(['a. Philippine Residents']);
//     sheet.appendRow(['b. Non-Philippine/Foreign Residents (including unspecified)']);
//     sheet.appendRow(['c. Overseas Filipinos']);
//     sheet.appendRow(['d. Others/Unspecified Guest']);
//     sheet.appendRow(['x. Total']);
//     sheet.appendRow(['2. Female']);
//     sheet.appendRow(['a. Philippine Residents']);
//     sheet.appendRow(['b. Non-Philippine/Foreign Residents (including unspecified)']);
//     sheet.appendRow(['c. Overseas Filipinos']);
//     sheet.appendRow(['d. Others/Unspecified Guest']);
//     sheet.appendRow(['x. Total']);
//   }
// }