import 'package:flutter/material.dart';

import '../services/cloud_settings.dart';

class CloudSettingsPage extends StatefulWidget {
  const CloudSettingsPage({
    required this.store,
    required this.initialSettings,
    super.key,
  });

  final CloudSettingsStore store;
  final CloudSettings initialSettings;

  @override
  State<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends State<CloudSettingsPage> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _baseUrlController;
  late final TextEditingController _modelController;
  late bool _enabled;
  bool _obscureApiKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSettings;
    _enabled = initial.enabled;
    _apiKeyController = TextEditingController(text: initial.apiKey);
    _baseUrlController = TextEditingController(text: initial.baseUrl);
    _modelController = TextEditingController(text: initial.model);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();
    if (baseUrl.isEmpty || model.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Base URL 和模型不能为空')));
      return;
    }
    setState(() => _saving = true);
    final settings = CloudSettings(
      enabled: _enabled,
      apiKey: _apiKeyController.text.trim(),
      baseUrl: baseUrl,
      model: model,
    );
    try {
      await widget.store.write(settings);
      if (mounted) Navigator.of(context).pop(settings);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型与云端设置'),
        actions: <Widget>[
          TextButton(
            key: const Key('saveCloudSettings'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            SwitchListTile(
              key: const Key('cloudEnabledSwitch'),
              contentPadding: EdgeInsets.zero,
              title: const Text('启用云端'),
              subtitle: const Text('开启后，任务文本会发送到第三方服务器。关闭时所有解析均留在设备上。'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('cloudApiKey'),
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: Wrap(
                  children: <Widget>[
                    IconButton(
                      key: const Key('toggleApiKeyVisibility'),
                      tooltip: _obscureApiKey ? '显示' : '隐藏',
                      onPressed: () {
                        setState(() => _obscureApiKey = !_obscureApiKey);
                      },
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                    ),
                    IconButton(
                      key: const Key('clearApiKey'),
                      tooltip: '清除',
                      onPressed: _apiKeyController.clear,
                      icon: const Icon(Icons.clear),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('cloudBaseUrl'),
              controller: _baseUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('cloudModel'),
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
