const _countryToReportFormat = {
  'CIS': 'COMMONWEALTH OF INDEPENDENT STATES',
  'Hong Kong': 'HONGKONG',
  'Papua NG': 'PAPUA NEW GUINEA',
  'Serbia & Montenegro': 'UNION OF SERBIA AND MONTENEGRO',
  'UAE': 'UNITED ARAB EMIRATES',
};

const _reportFormatToCountry = {
  'COMMONWEALTH OF INDEPENDENT STATES': 'CIS',
  'HONGKONG': 'Hong Kong',
  'PAPUA NEW GUINEA': 'Papua NG',
  'UNION OF SERBIA AND MONTENEGRO': 'Serbia & Montenegro',
  'UNITED ARAB EMIRATES': 'UAE',
};

String mapToReportFormat(String country) =>
    _countryToReportFormat[country] ?? country;

String mapFromReportFormat(String country) =>
    _reportFormatToCountry[country] ?? country;
