import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_colors.dart';

// ─── Colours ─────────────────────────────────────────────────────────────────

const kInputFill = Color(0xFFF8FAFC);
const kInputBorder = Color(0xFFD1D5DB);
const kInputFocused = Color(0xFF3B82F6);
const kDropBg = Color(0xFFFFFFFF);
const kInputText = Color(0xFF111827);
const kInputHint = Color(0xFF9CA3AF);
const kReadOnlyFill = Color(0xFFEFF2F5);

const kFieldHeight = 40.0;

// ─── Decoration helper ───────────────────────────────────────────────────────

InputDecoration lightDecoration({String? hint, bool hasError = false}) {
  final borderColor = hasError ? AppColors.accentRed : kInputBorder;
  final focusColor = hasError ? AppColors.accentRed : kInputFocused;
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kInputHint, fontSize: 13),
    filled: true,
    fillColor: hasError ? AppColors.accentRed.withOpacity(0.04) : kInputFill,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: focusColor, width: 1.4),
    ),
  );
}

// ─── Section Card ────────────────────────────────────────────────────────────

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: AppColors.primaryCyan,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

// ─── Field Column ────────────────────────────────────────────────────────────

class FieldCol extends StatelessWidget {
  const FieldCol({super.key, required this.label, required this.child, this.errorText});

  final String label;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        child,
        if (errorText != null) ...[
          const SizedBox(height: 5),
          InlineError(message: errorText!),
        ],
      ],
    );
  }
}

// ─── Inline Error ────────────────────────────────────────────────────────────

class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, size: 12, color: AppColors.accentRed),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: AppColors.accentRed,
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Date Field ──────────────────────────────────────────────────────────────

class EntryDateField extends StatelessWidget {
  const EntryDateField({
    super.key,
    required this.value,
    required this.onTap,
    this.hasError = false,
  });
  final String value;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: kFieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: hasError ? AppColors.accentRed.withOpacity(0.04) : kInputFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasError ? AppColors.accentRed : kInputBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value.isEmpty ? 'yyyy-mm-dd' : value,
                style: TextStyle(
                  color: value.isEmpty ? kInputHint : kInputText,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              color: hasError ? AppColors.accentRed : kInputHint,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Read-Only Field ─────────────────────────────────────────────────────────

class EntryReadOnlyField extends StatelessWidget {
  const EntryReadOnlyField({super.key, required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kReadOnlyFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kInputBorder),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        value,
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
      ),
    );
  }
}

// ─── Number Field ────────────────────────────────────────────────────────────

class EntryNumberField extends StatelessWidget {
  const EntryNumberField({
    super.key,
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
    this.readOnly = false,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    if (readOnly) {
      return EntryReadOnlyField(value: controller.text.isEmpty ? hint : controller.text);
    }
    return SizedBox(
      height: kFieldHeight,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: onChanged,
        style: const TextStyle(color: kInputText, fontSize: 13),
        decoration: lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

// ─── Text Field ──────────────────────────────────────────────────────────────

class EntryTextField extends StatelessWidget {
  const EntryTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.hasError = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool hasError;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: kInputText, fontSize: 13),
        decoration: lightDecoration(hint: hint, hasError: hasError),
      ),
    );
  }
}

// ─── Dropdown Field ──────────────────────────────────────────────────────────

class EntryDropdownField extends StatelessWidget {
  const EntryDropdownField({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.hint = 'Select option',
    this.hasError = false,
    this.displayLabels,
  });
  final String? value;
  final List<String> items;
  final ValueChanged<String?>? onChanged;
  final String hint;
  final bool hasError;
  final Map<String, String>? displayLabels;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: hasError ? AppColors.accentRed.withOpacity(0.04) : kInputFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? AppColors.accentRed : kInputBorder,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: const TextStyle(color: kInputHint, fontSize: 13),
          ),
          dropdownColor: kDropBg,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: hasError ? AppColors.accentRed : kInputHint,
          ),
          style: const TextStyle(color: kInputText, fontSize: 13),
          items: items
              .map(
                (e) => DropdownMenuItem<String>(
                  value: e,
                  child: Text(
                    displayLabels?[e] ?? e,
                    style: const TextStyle(color: kInputText, fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
