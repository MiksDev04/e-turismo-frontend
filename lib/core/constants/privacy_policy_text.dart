const String kPrivacyPolicyVersion = '1.0';

const String kDpoEmail = 'tourismoffice.sanpablo@gmail.com';

class PolicySection {
  final String heading;
  final String body;
  final List<String> bullets;
  const PolicySection(this.heading, this.body, {this.bullets = const []});
}

// Sections 1 to 9: shown to every account type
const List<PolicySection> kPolicySectionsCommon = [
  PolicySection(
    '1. Introduction',
    'By registering for an E-Turismo account, you acknowledge that you have read, understood, and agree to these Terms of Use and this Data Privacy Notice. E-Turismo is a tourism management system for San Pablo City, operated for the City Tourism Office (the "Personal Information Controller").',
  ),
  PolicySection(
    '2. Applicable Laws',
    'This notice is issued in accordance with the following laws of the Republic of the Philippines and their implementing rules and regulations:',
    bullets: [
      'Republic Act No. 10173, the Data Privacy Act of 2012;',
      'Republic Act No. 8792, the Electronic Commerce Act of 2000;',
      'Republic Act No. 10175, the Cybercrime Prevention Act of 2012; and',
      'Republic Act No. 9593, the Tourism Act of 2009.',
    ],
  ),
  PolicySection(
    '3. Personal Information We Collect',
    'Name, email address, contact number, business or attraction details, permit and registration information, and visitor or guest records encoded in the system.',
  ),
  PolicySection(
    '4. Purpose and Legal Basis of Processing',
    'Your personal data is processed solely for account verification, tourism statistics, official reports (DAE and VAR), and system notices, on the basis of your consent and the lawful tourism-reporting functions of the City Tourism Office.',
  ),
  PolicySection(
    '5. Disclosure and Sharing',
    'Personal data is disclosed only to authorized city and national government tourism offices for official reporting. E-Turismo does not sell, rent, or trade personal data to any third party.',
  ),
  PolicySection(
    '6. Retention and Security',
    'Personal data is retained only for as long as necessary to fulfill the purposes stated above or as required by law. Reasonable organizational, physical, and technical safeguards are implemented, including access controls and encrypted transmission.',
  ),
  PolicySection(
    '7. Your Rights as a Data Subject',
    'Under RA 10173, you have the right to be informed, to access, to object, to rectify, to erasure or blocking, to data portability, to withdraw consent, to be indemnified for damages, and to file a complaint with the National Privacy Commission (www.privacy.gov.ph).',
  ),
  PolicySection(
    '8. Acceptable Use',
    'You agree to provide accurate and truthful information, keep your credentials confidential, and use the system only for lawful tourism-related purposes. Unauthorized access, impersonation, falsification of records, data tampering, or any act that interferes with the system may constitute an offense under RA 10175 and may result in account suspension and legal action.',
  ),
  PolicySection(
    '9. Electronic Consent',
    'In accordance with RA 8792, your electronic acceptance of this notice, by ticking the checkbox and selecting "I Agree", constitutes your consent to these terms.',
  ),
];

// Section 10: shown only when accountType is 'business' or 'attraction'
const PolicySection kPolicySectionBusinessAttraction = PolicySection(
  '10. Business and Attraction Accounts',
  'You are responsible for the guest and visitor information you encode. Such data shall be used solely for tourism reporting and you shall inform your guests and visitors of its collection and use.',
);

// Section 11: shown only when accountType is 'admin'
const PolicySection kPolicySectionAdmin = PolicySection(
  '11. Administrator Accounts',
  'You shall treat all personal data accessed through the system as confidential and use it only for official duties.',
);

// Section 12: shown to every account type, always last
const PolicySection kPolicySectionContact = PolicySection(
  '12. Changes and Contact',
  'This notice may be updated, and continued use of the system after an update constitutes acceptance of the revised version. For privacy concerns or to exercise your rights, contact the Data Protection Officer at $kDpoEmail.',
);
