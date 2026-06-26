import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/app_colors.dart';
import '../../doctor/widgets/doctor_empty_state.dart';
import '../../doctor/widgets/doctor_page_scaffold.dart';
import '../../doctor/widgets/doctor_theme.dart';
import '../services/caregiver_emergency_service.dart';

class CaregiverEmergencyPage extends StatefulWidget {
  const CaregiverEmergencyPage({super.key});

  @override
  State<CaregiverEmergencyPage> createState() => _CaregiverEmergencyPageState();
}

class _CaregiverEmergencyPageState extends State<CaregiverEmergencyPage> {
  final _service = CaregiverEmergencyService();
  String? _selectedDocId;

  Future<void> _resolveAlert(CaregiverEmergencyAlert alert) async {
    try {
      await _service.resolveAlert(alert.docId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert marked as resolved.')),
      );
      if (_selectedDocId == alert.docId) {
        setState(() => _selectedDocId = null);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DoctorPageScaffold(
      title: 'Emergency',
      body: StreamBuilder<List<CaregiverEmergencyAlert>>(
        stream: _service.watchOpenAlerts(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }

          final alerts = snapshot.data!;
          final selected = _selectedDocId == null
              ? (alerts.isNotEmpty ? alerts.first : null)
              : alerts.cast<CaregiverEmergencyAlert?>().firstWhere(
                    (alert) => alert?.docId == _selectedDocId,
                    orElse: () => alerts.isNotEmpty ? alerts.first : null,
                  );

          if (alerts.isEmpty) {
            return const DoctorEmptyState(
              icon: Icons.emergency_outlined,
              message: 'No active emergencies',
              detail:
                  'When a connected patient sends an SOS alert, their location will appear here.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Active alerts from connected patients',
                style: TextStyle(color: AppColors.subtext, fontSize: 14),
              ),
              const SizedBox(height: 12),
              ...alerts.map((alert) => _AlertCard(
                    alert: alert,
                    selected: selected?.docId == alert.docId,
                    onTap: () => setState(() => _selectedDocId = alert.docId),
                    onResolve: () => _resolveAlert(alert),
                  )),
              if (selected != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Patient location — ${selected.patientName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                _EmergencyMap(alert: selected),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.selected,
    required this.onTap,
    required this.onResolve,
  });

  final CaregiverEmergencyAlert alert;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final entity = alert.entity;
    final coords = CaregiverEmergencyService.parseGpsLocation(entity.location);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: DoctorTheme.cardRadius,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? DoctorTheme.dangerSurface : DoctorTheme.surfaceElevated,
              borderRadius: DoctorTheme.cardRadius,
              border: Border.all(
                color: selected ? DoctorTheme.dangerBorder : DoctorTheme.borderSoft,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        entity.alertType.toLowerCase().contains('fall')
                            ? Icons.personal_injury_outlined
                            : Icons.warning_amber_rounded,
                        color: Colors.red.shade300,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.patientName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '${entity.alertType} • ${entity.alertId}',
                              style: const TextStyle(
                                color: AppColors.subtext,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Chip(
                        label: Text(
                          entity.status,
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: Colors.red.shade700,
                        labelStyle: const TextStyle(color: Colors.white),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Time: ${entity.dateTime}',
                    style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    coords != null
                        ? 'GPS: ${coords.lat.toStringAsFixed(6)}, ${coords.lng.toStringAsFixed(6)}'
                        : entity.location,
                    style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Mark as Resolved'),
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmergencyMap extends StatelessWidget {
  const _EmergencyMap({required this.alert});

  final CaregiverEmergencyAlert alert;

  @override
  Widget build(BuildContext context) {
    final coords =
        CaregiverEmergencyService.parseGpsLocation(alert.entity.location);
    if (coords == null) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: DoctorTheme.surfaceCard(),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'GPS coordinates are not available for this alert.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.subtext),
          ),
        ),
      );
    }

    final point = LatLng(coords.lat, coords.lng);
    return ClipRRect(
      borderRadius: DoctorTheme.cardRadius,
      child: SizedBox(
        height: 260,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.auraguide.mobile',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 48,
                  height: 48,
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 44,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
