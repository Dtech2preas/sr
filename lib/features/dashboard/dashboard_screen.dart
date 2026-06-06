import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/server_manager.dart';
import '../../core/visitor_tracker.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
      appBar: AppBar(
        title: const Text('DTech Server'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(context, serverManager, visitorTracker),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _pickFolder(context),
              icon: const Icon(Icons.folder),
              label: Text(serverManager.websiteFolder ?? 'Select Website Folder'),
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
                backgroundColor: serverManager.isRunning ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                serverManager.isRunning ? 'Stop Server' : 'Start Server',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Recent Requests:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
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
                    final reversedIndex = visitorTracker.recentRequests.length - 1 - index;
                    return Text(
                      visitorTracker.recentRequests[reversedIndex],
                      style: const TextStyle(fontFamily: 'monospace'),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, ServerManager serverManager, VisitorTracker visitorTracker) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Status: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Icon(
                  serverManager.isRunning ? Icons.circle : Icons.circle_outlined,
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
              const Text('Public URL:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(
                'http://${serverManager.ipAddress}:${serverManager.port}',
                style: TextStyle(color: Theme.of(context).colorScheme.secondary),
              ),
            ],
            const SizedBox(height: 8),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Visitors:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('${visitorTracker.visitorCount}', style: const TextStyle(fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
