// ─── Models ───────────────────────────────────────────────────────────────────

enum MessageType { compliance, announcement, general }

class Message {
  const Message({
    required this.type,
    required this.subject,
    required this.recipient,
    required this.date,
  });

  final MessageType type;
  final String subject;
  final String recipient;
  final String date;
}
