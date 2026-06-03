/// A bookable time from Firestore `appointments` (`dateTime` + document id).
class BookableSlot {
  const BookableSlot({
    required this.dateTime,
    required this.firestoreDocId,
    this.appointmentId,
  });

  final DateTime dateTime;
  /// `appointments/{id}` document id (e.g. A00003).
  final String firestoreDocId;
  final String? appointmentId;

  bool get hasExistingDocument => firestoreDocId.isNotEmpty;
}
