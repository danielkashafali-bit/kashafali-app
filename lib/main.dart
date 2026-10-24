import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// Adresse de votre serveur de restauration (modifiable au build avec
/// --dart-define=RESTORE_ENDPOINT=https://votre-serveur/restore).
/// Contrat : POST multipart, champ "image" -> renvoie l'image restaurée (octets).
const String kRestoreEndpoint = String.fromEnvironment(
  'RESTORE_ENDPOINT',
  defaultValue: 'https://VOTRE-SERVEUR.com/restore',
);

/// Clé API envoyée au serveur (en-tête X-API-Key).
/// Ne l'écrivez pas dans le code : passez-la au build avec
///   flutter build appbundle --dart-define=KASHAFALI_API_KEY=votre-clé
const String kApiKey = String.fromEnvironment('KASHAFALI_API_KEY');

void main() => runApp(const KashafaliApp());

class KashafaliApp extends StatelessWidget {
  const KashafaliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'kashafali',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF6C4DFF),
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _picker = ImagePicker();
  final _captureKey = GlobalKey();

  Uint8List? _original;
  Uint8List? _restored;
  bool _loading = false;
  bool _showOriginal = false;

  double _brightness = 0; // -0.3 .. 0.3
  double _contrast = 1; // 0.7 .. 1.4
  double _saturation = 1; // 0 .. 2

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  void _resetAdjustments() {
    _brightness = 0;
    _contrast = 1;
    _saturation = 1;
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 3000,
      imageQuality: 95,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _original = bytes;
      _restored = null;
      _resetAdjustments();
    });
  }

  Future<void> _restore() async {
    if (_original == null) return;
    setState(() => _loading = true);
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(kRestoreEndpoint))
            ..headers['X-API-Key'] = kApiKey
            ..files.add(http.MultipartFile.fromBytes(
              'image',
              _original!,
              filename: 'photo.jpg',
            ));
      final response =
          await request.send().timeout(const Duration(minutes: 2));
      if (response.statusCode != 200) {
        throw Exception('serveur (${response.statusCode})');
      }
      final bytes = await response.stream.toBytes();
      setState(() {
        _restored = bytes;
        _resetAdjustments();
      });
    } catch (e) {
      _snack('Échec de la restauration : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(
        data.buffer.asUint8List(),
        name: 'kashafali_${DateTime.now().millisecondsSinceEpoch}',
      );
      _snack('Photo enregistrée dans la galerie');
    } catch (e) {
      _snack('Échec de l\'enregistrement : $e');
    }
  }

  ColorFilter _saturationFilter(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return ColorFilter.matrix(<double>[
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  ColorFilter _contrastBrightnessFilter(double c, double b) {
    final t = 128 * (1 - c) + b * 255;
    return ColorFilter.matrix(<double>[
      c, 0, 0, 0, t, //
      0, c, 0, 0, t,
      0, 0, c, 0, t,
      0, 0, 0, 1, 0,
    ]);
  }

  Widget _preview() {
    if (_original == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add_photo_alternate_outlined, size: 72),
            SizedBox(height: 12),
            Text('Choisissez une photo à restaurer'),
          ],
        ),
      );
    }

    final showRestored = _restored != null && !_showOriginal;
    final Widget image = showRestored
        ? RepaintBoundary(
            key: _captureKey,
            child: ColorFiltered(
              colorFilter: _saturationFilter(_saturation),
              child: ColorFiltered(
                colorFilter:
                    _contrastBrightnessFilter(_contrast, _brightness),
                child: Image.memory(_restored!, fit: BoxFit.contain),
              ),
            ),
          )
        : Image.memory(_original!, fit: BoxFit.contain);

    return GestureDetector(
      onLongPressStart: (_) => setState(() => _showOriginal = true),
      onLongPressEnd: (_) => setState(() => _showOriginal = false),
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          Positioned.fill(child: Center(child: image)),
          if (_restored != null)
            Positioned(
              top: 8,
              left: 8,
              child: Chip(
                label: Text(showRestored ? 'Restaurée' : 'Originale'),
              ),
            ),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('kashafali'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _preview()),
            if (_restored != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const Text(
                      'Maintenez appuyé sur la photo pour voir l\'originale',
                      style: TextStyle(fontSize: 12),
                    ),
                    _slider('Luminosité', _brightness, -0.3, 0.3,
                        (v) => setState(() => _brightness = v)),
                    _slider('Contraste', _contrast, 0.7, 1.4,
                        (v) => setState(() => _contrast = v)),
                    _slider('Saturation', _saturation, 0, 2,
                        (v) => setState(() => _saturation = v)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _loading ? null : () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Galerie'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _loading ? null : () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Appareil photo'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_original == null || _loading) ? null : _restore,
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Restaurer'),
                        ),
                      ),
                      if (_restored != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _save,
                            icon: const Icon(Icons.download),
                            label: const Text('Enregistrer'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
