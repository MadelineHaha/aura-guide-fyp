import '../utils/clinic_datetime.dart';

class AppointmentItem {
  AppointmentItem({
    required this.id,
    required this.doctorName,
    required this.specialty,
    required this.dateTime,
    required this.location,
    required this.status,
  });

  final String id;
  final String doctorName;
  final String specialty;
  final DateTime dateTime;
  final String location;
  final String status;

  bool get isPast => ClinicDateTime.isBeforeNow(dateTime);

  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' || status.toLowerCase() == 'done';

  bool get isPending => status.toLowerCase() == 'pending';

  String get locationDisplay {
    if (isPending) return 'Location pending confirmation';
    if (location.isEmpty) return '—';
    return location;
  }

  String get dateLabel {
    final y = dateTime.year;
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get timeLabel {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $period';
  }
}
