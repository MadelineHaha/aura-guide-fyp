/// Row for Health Records list (Firestore `healthrecords`).
class HealthRecordItem {
  const HealthRecordItem({
    required this.recordId,
    required this.recordType,
    required this.dateCreated,
    required this.doctorName,
    required this.summary,
    required this.fileType,
    required this.filePath,
    required this.hasInlineFile,
    required this.userId,
  });

  final String recordId;
  /// Card title (Firestore `recordType`).
  final String recordType;
  /// Display date `YYYY-MM-DD` (Firestore `dateCreated`).
  final String dateCreated;
  final String doctorName;
  /// Clinical summary (Firestore `title`).
  final String summary;
  final String fileType;
  final String filePath;
  final bool hasInlineFile;
  final String userId;
}
