import 'package:collection/collection.dart';
import 'package:firmware_updater/detail_page.dart';
import 'package:firmware_updater/device_store.dart';
import 'package:firmware_updater/device_tile.dart';
import 'package:firmware_updater/fwupd_dbus_service.dart';
import 'package:firmware_updater/fwupd_l10n.dart';
import 'package:firmware_updater/fwupd_mock_service.dart';
import 'package:firmware_updater/fwupd_notifier.dart';
import 'package:firmware_updater/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:fwupd/fwupd.dart';
import 'package:gtk/gtk.dart';
import 'package:provider/provider.dart';
import 'package:ubuntu_service/ubuntu_service.dart';
import 'package:yaru_widgets/yaru_widgets.dart';

class FirmwareApp extends StatefulWidget {
  const FirmwareApp({super.key});

  static Widget create(BuildContext context) {
    final service = hasService<FwupdMockService>()
        ? getService<FwupdMockService>()
        : getService<FwupdDbusService>();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DeviceStore(service)),
        ChangeNotifierProvider(create: (_) => FwupdNotifier(service)),
      ],
      child: const FirmwareApp(),
    );
  }

  @override
  State<FirmwareApp> createState() => _FirmwareAppState();
}

class _FirmwareAppState extends State<FirmwareApp> {
  YaruPageController? _controller;
  bool _initialized = false;
  bool _onBattery = false;

  @override
  void initState() {
    super.initState();
    final fwupdNotifier = context.read<FwupdNotifier>();
    final store = context.read<DeviceStore>();
    final gtkNotifier = getService<GtkApplicationNotifier>();

    fwupdNotifier
      ..init()
      ..registerErrorListener(_showError)
      ..registerConfirmationListener(_getConfirmation)
      ..registerDeviceRequestListener(_showRequest);
    store.init().then((_) {
      _controller = YaruPageController(length: store.devices.length);
      _commandLineListener(gtkNotifier.commandLine!);
      setState(() {
        _initialized = true;
      });
    });
    gtkNotifier.addCommandLineListener(_commandLineListener);

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final l10n = AppLocalizations.of(context);
      if (_onBattery) {
        await _showAlertDialog(l10n.acPowerTitle, l10n.acPowerMustBeSupplied);
      }
    });
  }

  Future<dynamic> _showAlertDialog(String titleP, String contentP) {
    return showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        // return object of type Dialog
        return AlertDialog(
          title: Text(titleP),
          content: Text(contentP),
          actions: <Widget>[
            // usually buttons at the bottom of the dialog
            TextButton(
              child: Text(l10n.ok),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    final gtkNotifier = getService<GtkApplicationNotifier>();
    gtkNotifier.removeCommandLineListener(_commandLineListener);
    super.dispose();
  }

  void _commandLineListener(List<String> args) {
    final store = context.read<DeviceStore>();
    _controller?.index = store.indexOf(args.firstOrNull);
    store.showReleases = args.isNotEmpty;
  }

  void _showRequest(FwupdDevice device) {
    showDeviceRequestDialog(
      context,
      message: device.updateMessage,
      imageUrl: device.updateImage,
    );
  }

  void _showError(Exception e) {
    showErrorDialog(
      context,
      title: AppLocalizations.of(context).installError,
      message: e is FwupdException ? e.localize(context) : e.toString(),
    );
  }

  Future<bool> _getConfirmation() async {
    final l10n = AppLocalizations.of(context);
    final response = await showConfirmationDialog(
      context,
      message: l10n.rebootConfirmMessage,
      title: l10n.rebootConfirmTitle,
      actionText: l10n.rebootNow,
      cancelText: l10n.rebootLater,
      isPrimaryAction: false,
    );

    return response == DialogAction.secondaryAction;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DeviceStore>();
    final l10n = AppLocalizations.of(context);
    _onBattery =
        context.select<FwupdNotifier, bool>((notifier) => notifier.onBattery);
    return _initialized
        ? Center(
            child: YaruMasterDetailPage(
              appBar: YaruWindowTitleBar(title: Text(l10n.appTitle)),
              controller: _controller,
              onSelected: (value) {
                store.showReleases = false;
              },
              pageBuilder: (context, index) =>
                  DetailPage.create(context, device: store.devices[index]),
              tileBuilder: (context, index, selected, availableWidth) =>
                  DeviceTile.create(context, device: store.devices[index]),
              emptyBuilder: (_) => Scaffold(
                appBar: YaruWindowTitleBar(title: Text(l10n.appTitle)),
                body: Center(child: Text(l10n.noDevicesFound)),
              ),
            ),
          )
        : const Center(child: YaruCircularProgressIndicator());
  }
}
