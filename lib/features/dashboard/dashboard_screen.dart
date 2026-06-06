import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/server_manager.dart';
import '../../core/visitor_tracker.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _uptimeTimer;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Update UI every minute for uptime
    _uptimeTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uptimeTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickFolder(BuildContext context) async {
    // Request storage permission first
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      await Permission.storage.request();
    }

    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null && context.mounted) {
      context.read<ServerManager>().setWebsiteFolder(selectedDirectory);
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverManager = context.watch<ServerManager>();
    final visitorTracker = context.watch<VisitorTracker>();

    return Scaffold(
      appBar: AppBar(title: const Text('DTech Server')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatusCard(context, serverManager, visitorTracker),
              const SizedBox(height: 16),
              if (serverManager.websiteFolder == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.folder_open, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text(
                        'No folder selected.\nSelect a folder containing your website files (e.g. index.html) to get started.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              if (serverManager.websiteFolder != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Auto-start server:'),
                    Switch(
                      value: serverManager.autoStart,
                      onChanged: (value) => serverManager.setAutoStart(value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Enable WebRTC P2P Tunnel (Internet Access):'),
                    Switch(
                      value: serverManager.tunnelEnabled,
                      onChanged: (value) =>
                          serverManager.setTunnelEnabled(value),
                    ),
                  ],
                ),
                if (serverManager.tunnelEnabled) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    initialValue: serverManager.subdomain,
                    decoration: const InputDecoration(
                      labelText: 'Subdomain (e.g. portfolio)',
                      border: OutlineInputBorder(),
                      suffixText: '.ulenabler.co.za',
                    ),
                    onChanged: (value) {
                      if (_debounceTimer?.isActive ?? false)
                        _debounceTimer!.cancel();
                      _debounceTimer = Timer(const Duration(seconds: 1), () {
                        serverManager.setSubdomain(value);
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => _pickFolder(context),
                icon: const Icon(Icons.folder),
                label: Text(
                  serverManager.websiteFolder ?? 'Select Website Folder',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: serverManager.websiteFolder == null
                    ? null
                    : () async {
                        try {
                          if (serverManager.isRunning) {
                            await serverManager.stopServer();
                          } else {
                            await serverManager.startServer();
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: $e')),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: serverManager.isRunning
                      ? Colors.red
                      : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  serverManager.isRunning ? 'Stop Server' : 'Start Server',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Recent Requests:',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: visitorTracker.recentRequests.isEmpty
                        ? null
                        : () => visitorTracker.clearLogs(),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                  ),
                ],
              ),
              Container(
                height: 250,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: visitorTracker.recentRequests.length,
                  itemBuilder: (context, index) {
                    // Show newest first
                    final reversedIndex =
                        visitorTracker.recentRequests.length - 1 - index;
                    final logEntry =
                        visitorTracker.recentRequests[reversedIndex];

                    Color methodColor = Colors.white;
                    if (logEntry.startsWith('GET'))
                      methodColor = Colors.greenAccent;
                    else if (logEntry.startsWith('POST'))
                      methodColor = Colors.blueAccent;
                    else if (logEntry.startsWith('PUT') ||
                        logEntry.startsWith('PATCH'))
                      methodColor = Colors.orangeAccent;
                    else if (logEntry.startsWith('DELETE'))
                      methodColor = Colors.redAccent;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                      child: Text(
                        logEntry,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: methodColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    ServerManager serverManager,
    VisitorTracker visitorTracker,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Status: ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Icon(
                  serverManager.isRunning
                      ? Icons.circle
                      : Icons.circle_outlined,
                  color: serverManager.isRunning ? Colors.green : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(serverManager.isRunning ? 'Running' : 'Stopped'),
              ],
            ),
            const SizedBox(height: 8),
            Text('IP Address: ${serverManager.ipAddress}'),
            Text('Port: ${serverManager.port}'),
            const SizedBox(height: 8),
            if (serverManager.isRunning) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Public URL: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Expanded(
                    child: SelectableText(
                      'http://${serverManager.ipAddress}:${serverManager.port}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy URL',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text:
                              'http://${serverManager.ipAddress}:${serverManager.port}',
                        ),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('URL copied to clipboard'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              if (serverManager.tunnelEnabled &&
                  serverManager.subdomain.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'Internet URL: ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: SelectableText(
                        'https://${serverManager.subdomain}.ulenabler.co.za',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy URL',
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text:
                                'https://${serverManager.subdomain}.ulenabler.co.za',
                          ),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Internet URL copied to clipboard'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: QrImageView(
                    data:
                        serverManager.tunnelEnabled &&
                            serverManager.subdomain.isNotEmpty
                        ? 'https://${serverManager.subdomain}.ulenabler.co.za'
                        : 'http://${serverManager.ipAddress}:${serverManager.port}',
                    version: QrVersions.auto,
                    size: 150.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Uptime:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  serverManager.isRunning
                      ? '${serverManager.uptime.inHours.toString().padLeft(2, '0')}:${(serverManager.uptime.inMinutes % 60).toString().padLeft(2, '0')}'
                      : '00:00',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Visitors:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${visitorTracker.visitorCount}',
                  style: const TextStyle(fontSize: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
