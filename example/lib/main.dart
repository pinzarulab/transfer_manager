import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TransferManagerExampleApp());
}

class TransferManagerExampleApp extends StatelessWidget {
  const TransferManagerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Transfer Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff155eef)),
        useMaterial3: true,
      ),
      home: const DownloadsPage(),
    );
  }
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  static const _downloads = [
    DownloadOption(
      title: 'Small sample',
      subtitle: 'A quick 1 MB download',
      fileName: 'cloudflare-1mb.bin',
      bytes: 1000000,
      icon: Icons.description_outlined,
    ),
    DownloadOption(
      title: 'Medium sample',
      subtitle: 'A 10 MB background download',
      fileName: 'cloudflare-10mb.bin',
      bytes: 10000000,
      icon: Icons.archive_outlined,
    ),
    DownloadOption(
      title: 'Large sample',
      subtitle: 'A 50 MB background download',
      fileName: 'cloudflare-50mb.bin',
      bytes: 50000000,
      icon: Icons.movie_outlined,
    ),
  ];

  final Map<String, DownloadTaskView> _taskViews = {};
  final List<StreamSubscription<TransferEvent>> _subscriptions = [];

  TransferManager? _manager;
  TransferManagerIos? _iosPlatform;
  StreamSubscription<IosTransferNotificationResponse>?
  _notificationResponseSubscription;
  Directory? _downloadDirectory;
  bool _initializing = true;
  bool _requestingNotifications = false;
  bool _notificationsEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw UnsupportedError('This example supports Android and iOS.');
      }

      final supportDirectory = await getApplicationSupportDirectory();
      final downloadDirectory = Platform.isIOS
          ? Directory(
              '${(await getApplicationDocumentsDirectory()).path}'
              '${Platform.pathSeparator}downloads',
            )
          : null;
      await downloadDirectory?.create(recursive: true);

      final iosPlatform = Platform.isIOS ? TransferManagerIos() : null;
      final manager = TransferManager(
        storage: JsonFileTransferStorage(
          File(
            '${supportDirectory.path}${Platform.pathSeparator}'
            'transfer_manager${Platform.pathSeparator}tasks.json',
          ),
        ),
        configuration: const TransferConfiguration(
          maxConcurrentTasks: 3,
          maxConcurrentDownloads: 3,
        ),
        engines: [
          if (Platform.isAndroid) AndroidBackgroundDownloadEngine(),
          if (iosPlatform != null)
            IosBackgroundDownloadEngine(platform: iosPlatform),
          HttpTransferEngine(),
        ],
      );
      await manager.initialize();

      for (final task in await manager.tasks()) {
        _attachTask(task);
      }

      final notificationsEnabled = iosPlatform != null
          ? await iosPlatform.notificationsEnabled()
          : await _notificationsAreEnabled();
      if (!mounted) return;
      setState(() {
        _manager = manager;
        _iosPlatform = iosPlatform;
        _downloadDirectory = downloadDirectory;
        _notificationsEnabled = notificationsEnabled;
        _initializing = false;
      });
      if (iosPlatform != null) {
        _notificationResponseSubscription = iosPlatform.notificationResponses
            .listen(_openDownloadsFolderFromNotification);
        final initialResponse = await iosPlatform
            .takeInitialNotificationResponse();
        if (initialResponse != null) {
          _openDownloadsFolderFromNotification(initialResponse);
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  Future<bool> _notificationsAreEnabled() {
    if (Platform.isAndroid) {
      return TransferManagerAndroid().notificationsEnabled();
    }
    return (_iosPlatform ?? TransferManagerIos()).notificationsEnabled();
  }

  Future<bool> _requestNotificationPermission() {
    if (Platform.isAndroid) {
      return TransferManagerAndroid().requestNotificationPermission();
    }
    return (_iosPlatform ?? TransferManagerIos())
        .requestNotificationPermission();
  }

  Future<void> _enableNotifications() async {
    if (_requestingNotifications) return;
    setState(() => _requestingNotifications = true);
    try {
      final enabled = await _requestNotificationPermission();
      if (!mounted) return;
      setState(() => _notificationsEnabled = enabled);
      if (!enabled) {
        _showMessage(
          'Notifications are disabled. Downloads still work, but completion '
          'alerts will not be shown.',
        );
      }
    } catch (error) {
      if (mounted) _showMessage('Could not request permission: $error');
    } finally {
      if (mounted) setState(() => _requestingNotifications = false);
    }
  }

  Future<void> _startDownload(DownloadOption option) async {
    final manager = _manager;
    if (manager == null) return;

    if (!_notificationsEnabled) {
      await _enableNotifications();
    }

    try {
      final destination = Platform.isAndroid
          ? AndroidBackgroundDownloadEngine.downloadsDestination(
              option.fileName,
            )
          : '${_downloadDirectory!.path}'
                '${Platform.pathSeparator}${option.fileName}';
      final visibleDestination = Platform.isAndroid
          ? 'Downloads/${option.fileName}'
          : 'Files → On My iPhone/iPad → Transfer Manager → downloads'
                ' → ${option.fileName}';
      final task = await manager.enqueue(
        DownloadRequest(
          source: Uri.https('speed.cloudflare.com', '/__down', {
            'bytes': option.bytes.toString(),
          }),
          destinationPath: destination,
          existingFilePolicy: ExistingFilePolicy.replace,
          notification: TransferNotification(
            title: option.title,
            showProgress: true,
            allowPause: true,
            allowCancel: true,
          ),
        ),
      );
      _attachTask(task, option: option, destinationPath: visibleDestination);
      if (mounted) {
        setState(() {});
        _showMessage('${option.title} queued');
      }
    } catch (error) {
      if (mounted) _showMessage('Could not queue download: $error');
    }
  }

  void _attachTask(
    TransferTask task, {
    DownloadOption? option,
    String? destinationPath,
  }) {
    _taskViews[task.id] = DownloadTaskView(
      task: task,
      option: option,
      destinationPath: destinationPath,
    );
    _subscriptions.add(
      task.events.listen((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openDownloadsFolderFromNotification(
    IosTransferNotificationResponse response,
  ) {
    final directory = _downloadDirectory;
    if (!mounted || directory == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DownloadsFolderPage(
            directory: directory,
            selectedFilePath: response.filePath,
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_notificationResponseSubscription?.cancel());
    final manager = _manager;
    if (manager != null) unawaited(manager.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Background downloads')),
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!)
            : RefreshIndicator(
                onRefresh: _refreshNotificationStatus,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      'Choose a file',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'These downloads use WorkManager on Android and a '
                      'background URLSession on iOS. You can leave the app '
                      'while a transfer is running.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _NotificationCard(
                      enabled: _notificationsEnabled,
                      requesting: _requestingNotifications,
                      onEnable: _enableNotifications,
                    ),
                    const SizedBox(height: 16),
                    for (final option in _downloads) ...[
                      _DownloadOptionCard(
                        option: option,
                        onDownload: () => _startDownload(option),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Transfers',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_taskViews.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No downloads yet.'),
                        ),
                      )
                    else
                      for (final view in _taskViews.values.toList().reversed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TransferCard(view: view),
                        ),
                    const SizedBox(height: 8),
                    Text(
                      Platform.isAndroid
                          ? 'Files are saved in the system Downloads folder.'
                          : 'Files are available at:\n'
                                'Files → On My iPhone/iPad → '
                                'Transfer Manager → downloads',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Future<void> _refreshNotificationStatus() async {
    final enabled = await _notificationsAreEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }
}

class DownloadsFolderPage extends StatelessWidget {
  const DownloadsFolderPage({
    required this.directory,
    this.selectedFilePath,
    super.key,
  });

  final Directory directory;
  final String? selectedFilePath;

  Future<List<FileSystemEntity>> _files() async {
    final files = await directory
        .list()
        .where((entity) => entity is File)
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Downloads')),
      body: FutureBuilder<List<FileSystemEntity>>(
        future: _files(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not read downloads: ${snapshot.error}'),
            );
          }
          final files = snapshot.data ?? const [];
          if (files.isEmpty) {
            return const Center(child: Text('No downloaded files.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final selected = file.path == selectedFilePath;
              return Card(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                child: ListTile(
                  leading: Icon(
                    selected
                        ? Icons.insert_drive_file
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(Uri.file(file.path).pathSegments.last),
                  subtitle: Text(
                    selected ? 'Opened from notification' : file.path,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class DownloadOption {
  const DownloadOption({
    required this.title,
    required this.subtitle,
    required this.fileName,
    required this.bytes,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String fileName;
  final int bytes;
  final IconData icon;
}

class DownloadTaskView {
  const DownloadTaskView({
    required this.task,
    this.option,
    this.destinationPath,
  });

  final TransferTask task;
  final DownloadOption? option;
  final String? destinationPath;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.enabled,
    required this.requesting,
    required this.onEnable,
  });

  final bool enabled;
  final bool requesting;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: enabled ? colors.secondaryContainer : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              enabled
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                enabled
                    ? 'Download notifications are enabled.'
                    : Platform.isAndroid
                    ? 'Enable notifications for progress and completion.'
                    : 'Enable notifications for completion alerts.',
              ),
            ),
            if (!enabled)
              TextButton(
                onPressed: requesting ? null : onEnable,
                child: requesting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadOptionCard extends StatelessWidget {
  const _DownloadOptionCard({required this.option, required this.onDownload});

  final DownloadOption option;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(child: Icon(option.icon)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(option.subtitle),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.view});

  final DownloadTaskView view;

  @override
  Widget build(BuildContext context) {
    final task = view.task;
    final progress = task.progress;
    final fraction = progress.fraction;
    final isActive = {
      TransferState.created,
      TransferState.queued,
      TransferState.preparing,
      TransferState.running,
      TransferState.retryWaiting,
      TransferState.verifying,
    }.contains(task.state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    view.option?.title ?? 'Restored download',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StateChip(state: task.state),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: task.state == TransferState.completed ? 1 : fraction,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(progress.bytesTransferred)}'
              '${progress.totalBytes == null ? '' : ' / ${_formatBytes(progress.totalBytes!)}'}',
            ),
            if (task.error != null) ...[
              const SizedBox(height: 6),
              Text(
                task.error.toString(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (view.destinationPath != null &&
                task.state == TransferState.completed) ...[
              const SizedBox(height: 6),
              Text(
                view.destinationPath!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (isActive)
                  TextButton.icon(
                    onPressed: task.pause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                if (task.state == TransferState.paused)
                  TextButton.icon(
                    onPressed: task.resume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if (task.state == TransferState.failed)
                  TextButton.icon(
                    onPressed: task.retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                if (isActive || task.state == TransferState.paused)
                  TextButton.icon(
                    onPressed: task.cancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final TransferState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      TransferState.completed => Colors.green,
      TransferState.failed => Theme.of(context).colorScheme.error,
      TransferState.cancelled => Colors.grey,
      TransferState.paused => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    return Chip(
      label: Text(state.name),
      side: BorderSide(color: color),
      labelStyle: TextStyle(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '${(bytes / 1000000).toStringAsFixed(1)} MB';
}
