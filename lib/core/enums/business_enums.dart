// This file contains enums related to business types and statuses.
// These enums are used across the application to maintain consistency in representing business information.
enum BusinessType { corporation, partnership, soleProprietorship }

enum BusinessLine {
	hotel,
	resort,
	motel,
	pensionInn,
	youthHostel,
	apartment,
	others,
}

enum BusinessStatus { pending, approved, rejected }

extension BusinessTypeLabel on BusinessType {
	String get label => switch (this) {
				BusinessType.corporation => 'Corporation',
				BusinessType.partnership => 'Partnership',
				BusinessType.soleProprietorship => 'Sole Proprietorship',
			};
}

extension BusinessLineLabel on BusinessLine {
	String get label => switch (this) {
				BusinessLine.hotel => 'Hotel',
				BusinessLine.resort => 'Resort',
				BusinessLine.motel => 'Motel',
				BusinessLine.pensionInn => 'Pension Inn',
				BusinessLine.youthHostel => 'Youth Hostel',
				BusinessLine.apartment => 'Apartment',
				BusinessLine.others => 'Others',
			};
}