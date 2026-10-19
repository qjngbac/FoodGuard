import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/theme/app_theme.dart';

/// 交互式图片区域截取 / 裁剪页面
/// 用于在 OCR 前精准框选“配料表”或“营养成分表”区域，排除包装上的广告语、厂家、条码等无关噪音。
class ImageCropPage extends StatefulWidget {
  const ImageCropPage({super.key, required this.imagePath});

  final String imagePath;

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

enum _ActiveHandle {
  none,
  center,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topEdge,
  bottomEdge,
  leftEdge,
  rightEdge,
}

class _ImageCropPageState extends State<ImageCropPage> {
  ui.Image? _image;
  bool _loading = true;
  String? _error;
  int _rotationAngle = 0; // 0, 90, 180, 270

  // 屏幕上裁剪框相对于视口的坐标
  Rect? _cropRect;
  Rect? _displayedImageRect;
  Size _viewportSize = Size.zero;

  _ActiveHandle _activeHandle = _ActiveHandle.none;
  int _selectedPresetIndex = 0;
  Offset _dragStartPoint = Offset.zero;
  Rect _dragStartCropRect = Rect.zero;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final file = File(widget.imagePath);
      if (!file.existsSync()) {
        setState(() {
          _error = '图片文件不存在';
          _loading = false;
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _image = frame.image;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '图片解码失败：$e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  void _rotate90() {
    setState(() {
      _rotationAngle = (_rotationAngle + 90) % 360;
      _cropRect = null; // 旋转后重置裁剪框
    });
  }

  void _resetCrop({double? aspect}) {
    if (_displayedImageRect == null) return;
    final r = _displayedImageRect!;
    setState(() {
      if (aspect == null) {
        // 默认内缩 8% 作为初始选区
        _cropRect = Rect.fromLTWH(
          r.left + r.width * 0.05,
          r.top + r.height * 0.1,
          r.width * 0.9,
          r.height * 0.8,
        );
      } else {
        // 固定比例居中
        double targetW = r.width * 0.85;
        double targetH = targetW / aspect;
        if (targetH > r.height * 0.85) {
          targetH = r.height * 0.85;
          targetW = targetH * aspect;
        }
        final left = r.left + (r.width - targetW) / 2;
        final top = r.top + (r.height - targetH) / 2;
        _cropRect = Rect.fromLTWH(left, top, targetW, targetH);
      }
    });
  }

  void _fitAll() {
    if (_displayedImageRect == null) return;
    setState(() {
      _cropRect = _displayedImageRect;
    });
  }

  Future<void> _confirmCrop() async {
    if (_image == null || _cropRect == null || _displayedImageRect == null) {
      Navigator.of(context).pop(widget.imagePath);
      return;
    }

    final origW = (_rotationAngle == 90 || _rotationAngle == 270)
        ? _image!.height.toDouble()
        : _image!.width.toDouble();
    final origH = (_rotationAngle == 90 || _rotationAngle == 270)
        ? _image!.width.toDouble()
        : _image!.height.toDouble();

    final disp = _displayedImageRect!;
    final crop = _cropRect!;

    final relLeft = ((crop.left - disp.left) / disp.width).clamp(0.0, 1.0);
    final relTop = ((crop.top - disp.top) / disp.height).clamp(0.0, 1.0);
    // clamp 的下界必须不大于上界，否则视口变化后（旋转/分屏）会抛 ArgumentError 把页面卡死
    final maxRelW = (1.0 - relLeft).clamp(0.01, 1.0);
    final maxRelH = (1.0 - relTop).clamp(0.01, 1.0);
    final relWidth = (crop.width / disp.width).clamp(0.01, maxRelW);
    final relHeight = (crop.height / disp.height).clamp(0.01, maxRelH);

    final pixelX = (relLeft * origW).clamp(0.0, math.max<double>(0.0, origW - 10));
    final pixelY = (relTop * origH).clamp(0.0, math.max<double>(0.0, origH - 10));
    final pixelW = (relWidth * origW).clamp(1.0, math.max<double>(1.0, origW - pixelX));
    final pixelH = (relHeight * origH).clamp(1.0, math.max<double>(1.0, origH - pixelY));

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      canvas.save();
      canvas.translate(-pixelX, -pixelY);

      if (_rotationAngle == 90) {
        canvas.translate(origW, 0);
        canvas.rotate(math.pi / 2);
      } else if (_rotationAngle == 180) {
        canvas.translate(origW, origH);
        canvas.rotate(math.pi);
      } else if (_rotationAngle == 270) {
        canvas.translate(0, origH);
        canvas.rotate(3 * math.pi / 2);
      }

      canvas.drawImage(_image!, Offset.zero, Paint());
      canvas.restore();

      final picture = recorder.endRecording();
      final croppedImg = await picture.toImage(pixelW.toInt(), pixelH.toInt());
      final byteData = await croppedImg.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      croppedImg.dispose();

      if (byteData == null) {
        if (mounted) Navigator.of(context).pop(widget.imagePath);
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final croppedFile = File(
        '${tempDir.path}/crop_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await croppedFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

      if (mounted) {
        Navigator.of(context).pop(croppedFile.path);
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop(widget.imagePath);
    }
  }

  void _onPanStart(DragStartDetails details) {
    if (_cropRect == null || _displayedImageRect == null) return;
    final p = details.localPosition;
    _dragStartPoint = p;
    _dragStartCropRect = _cropRect!;

    const handleRadius = 24.0;
    const edgeMargin = 22.0;
    final r = _cropRect!;

    // 1. 优先判定四个角顶点
    if ((p - r.topLeft).distance <= handleRadius) {
      _activeHandle = _ActiveHandle.topLeft;
    } else if ((p - r.topRight).distance <= handleRadius) {
      _activeHandle = _ActiveHandle.topRight;
    } else if ((p - r.bottomLeft).distance <= handleRadius) {
      _activeHandle = _ActiveHandle.bottomLeft;
    } else if ((p - r.bottomRight).distance <= handleRadius) {
      _activeHandle = _ActiveHandle.bottomRight;
    }
    // 2. 判定四条边（在边框内外 edgeMargin 宽容度范围内，且在对应线段跨度内）
    else if ((p.dy - r.top).abs() <= edgeMargin &&
        p.dx >= r.left - edgeMargin &&
        p.dx <= r.right + edgeMargin) {
      _activeHandle = _ActiveHandle.topEdge;
    } else if ((p.dy - r.bottom).abs() <= edgeMargin &&
        p.dx >= r.left - edgeMargin &&
        p.dx <= r.right + edgeMargin) {
      _activeHandle = _ActiveHandle.bottomEdge;
    } else if ((p.dx - r.left).abs() <= edgeMargin &&
        p.dy >= r.top - edgeMargin &&
        p.dy <= r.bottom + edgeMargin) {
      _activeHandle = _ActiveHandle.leftEdge;
    } else if ((p.dx - r.right).abs() <= edgeMargin &&
        p.dy >= r.top - edgeMargin &&
        p.dy <= r.bottom + edgeMargin) {
      _activeHandle = _ActiveHandle.rightEdge;
    }
    // 3. 判定选区中心区域（整体平移）
    else if (r.contains(p)) {
      _activeHandle = _ActiveHandle.center;
    } else {
      _activeHandle = _ActiveHandle.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_cropRect == null || _displayedImageRect == null || _activeHandle == _ActiveHandle.none) {
      return;
    }

    final disp = _displayedImageRect!;
    final delta = details.localPosition - _dragStartPoint;
    final start = _dragStartCropRect;

    const minSize = 40.0;
    double left = start.left;
    double top = start.top;
    double right = start.right;
    double bottom = start.bottom;

    switch (_activeHandle) {
      case _ActiveHandle.center:
        final dx = delta.dx.clamp(disp.left - start.left, disp.right - start.right);
        final dy = delta.dy.clamp(disp.top - start.top, disp.bottom - start.bottom);
        setState(() {
          _cropRect = start.shift(Offset(dx, dy));
        });
        return;

      case _ActiveHandle.topLeft:
        left = (start.left + delta.dx).clamp(disp.left, start.right - minSize);
        top = (start.top + delta.dy).clamp(disp.top, start.bottom - minSize);
        break;

      case _ActiveHandle.topRight:
        right = (start.right + delta.dx).clamp(start.left + minSize, disp.right);
        top = (start.top + delta.dy).clamp(disp.top, start.bottom - minSize);
        break;

      case _ActiveHandle.bottomLeft:
        left = (start.left + delta.dx).clamp(disp.left, start.right - minSize);
        bottom = (start.bottom + delta.dy).clamp(start.top + minSize, disp.bottom);
        break;

      case _ActiveHandle.bottomRight:
        right = (start.right + delta.dx).clamp(start.left + minSize, disp.right);
        bottom = (start.bottom + delta.dy).clamp(start.top + minSize, disp.bottom);
        break;

      case _ActiveHandle.topEdge:
        top = (start.top + delta.dy).clamp(disp.top, start.bottom - minSize);
        break;

      case _ActiveHandle.bottomEdge:
        bottom = (start.bottom + delta.dy).clamp(start.top + minSize, disp.bottom);
        break;

      case _ActiveHandle.leftEdge:
        left = (start.left + delta.dx).clamp(disp.left, start.right - minSize);
        break;

      case _ActiveHandle.rightEdge:
        right = (start.right + delta.dx).clamp(start.left + minSize, disp.right);
        break;

      case _ActiveHandle.none:
        return;
    }

    setState(() {
      _cropRect = Rect.fromLTRB(left, top, right, bottom);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _activeHandle = _ActiveHandle.none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          '节选配料表区域',
          style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _rotate90,
            tooltip: '向右旋转90°',
            icon: const Icon(Icons.rotate_right, color: Colors.white),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _error != null
              ? Center(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      // 顶部温馨指引徽标
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.crop, size: 15, color: kPrimaryLight),
                            SizedBox(width: 6),
                            Text(
                              '拖动四角边框框选配料表，排除广告与厂家多余文字',
                              style: TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // 交互式图像视口
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

                            final origW = (_rotationAngle == 90 || _rotationAngle == 270)
                                ? _image!.height.toDouble()
                                : _image!.width.toDouble();
                            final origH = (_rotationAngle == 90 || _rotationAngle == 270)
                                ? _image!.width.toDouble()
                                : _image!.height.toDouble();

                            final imgAspect = origW / origH;
                            final viewAspect = _viewportSize.width / _viewportSize.height;

                            if (imgAspect > viewAspect) {
                              final h = _viewportSize.width / imgAspect;
                              _displayedImageRect = Rect.fromLTWH(
                                0,
                                (_viewportSize.height - h) / 2,
                                _viewportSize.width,
                                h,
                              );
                            } else {
                              final w = _viewportSize.height * imgAspect;
                              _displayedImageRect = Rect.fromLTWH(
                                (_viewportSize.width - w) / 2,
                                0,
                                w,
                                _viewportSize.height,
                              );
                            }

                            // 初始选区初始化
                            _cropRect ??= Rect.fromLTWH(
                              _displayedImageRect!.left + _displayedImageRect!.width * 0.05,
                              _displayedImageRect!.top + _displayedImageRect!.height * 0.1,
                              _displayedImageRect!.width * 0.9,
                              _displayedImageRect!.height * 0.8,
                            );

                            return GestureDetector(
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: CustomPaint(
                                size: _viewportSize,
                                painter: _CropPainter(
                                  image: _image!,
                                  displayedRect: _displayedImageRect!,
                                  cropRect: _cropRect!,
                                  rotationAngle: _rotationAngle,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // 快捷比例与复位标签
                      Container(
                        color: Colors.black.withValues(alpha: 0.85),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _presetChip(0, '自由框选', Icons.crop_free, () => _resetCrop()),
                              const SizedBox(width: 8),
                              _presetChip(1, '配料表横框', Icons.view_headline, () => _resetCrop(aspect: 2.2)),
                              const SizedBox(width: 8),
                              _presetChip(2, '营养表竖框', Icons.table_chart_outlined, () => _resetCrop(aspect: 0.65)),
                              const SizedBox(width: 8),
                              _presetChip(3, '全图选区', Icons.fullscreen, _fitAll),
                            ],
                          ),
                        ),
                      ),
                      // 底部主操作区
                      Container(
                        color: const Color(0xFF181818),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(widget.imagePath),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white30),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                child: const Text('使用全图识别', style: TextStyle(fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 6,
                              child: FilledButton.icon(
                                onPressed: _confirmCrop,
                                style: FilledButton.styleFrom(
                                  backgroundColor: kPrimary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(Icons.content_cut, size: 18),
                                label: const Text(
                                  '确认节选并识别',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _presetChip(int index, String label, IconData icon, VoidCallback onTap) {
    final isSelected = _selectedPresetIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _selectedPresetIndex = index);
          onTap();
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? kPrimary.withValues(alpha: 0.25) : const Color(0xFF262626),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? kPrimary : Colors.white24,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? kPrimaryLight : Colors.white70,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.displayedRect,
    required this.cropRect,
    required this.rotationAngle,
  });

  final ui.Image image;
  final Rect displayedRect;
  final Rect cropRect;
  final int rotationAngle;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 绘制图像
    canvas.save();
    canvas.translate(displayedRect.center.dx, displayedRect.center.dy);
    if (rotationAngle != 0) {
      canvas.rotate(rotationAngle * math.pi / 180);
    }
    final drawW = (rotationAngle == 90 || rotationAngle == 270)
        ? displayedRect.height
        : displayedRect.width;
    final drawH = (rotationAngle == 90 || rotationAngle == 270)
        ? displayedRect.width
        : displayedRect.height;

    paintImage(
      canvas: canvas,
      rect: Rect.fromCenter(center: Offset.zero, width: drawW, height: drawH),
      image: image,
      fit: BoxFit.fill,
    );
    canvas.restore();

    // 2. 绘制暗色半透明遮罩（镂空 cropRect）
    final maskPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(cropRect)
      ..fillType = PathFillType.evenOdd;

    final maskPaint = Paint()
      ..color = const Color(0xB3000000)
      ..style = PaintingStyle.fill;
    canvas.drawPath(maskPath, maskPaint);

    // 3. 绘制九宫格参考线
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final stepX = cropRect.width / 3;
    final stepY = cropRect.height / 3;
    canvas.drawLine(
      Offset(cropRect.left + stepX, cropRect.top),
      Offset(cropRect.left + stepX, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left + stepX * 2, cropRect.top),
      Offset(cropRect.left + stepX * 2, cropRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + stepY),
      Offset(cropRect.right, cropRect.top + stepY),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropRect.left, cropRect.top + stepY * 2),
      Offset(cropRect.right, cropRect.top + stepY * 2),
      gridPaint,
    );

    // 4. 绘制选区外边框
    final borderPaint = Paint()
      ..color = kPrimary
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRect(cropRect, borderPaint);

    // 5. 绘制四角 L 形加粗手柄
    final handlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    const cornerLen = 18.0;
    // 左上
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(cornerLen, 0), handlePaint);
    canvas.drawLine(cropRect.topLeft, cropRect.topLeft + const Offset(0, cornerLen), handlePaint);
    // 右上
    canvas.drawLine(cropRect.topRight, cropRect.topRight - const Offset(cornerLen, 0), handlePaint);
    canvas.drawLine(cropRect.topRight, cropRect.topRight + const Offset(0, cornerLen), handlePaint);
    // 左下
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft + const Offset(cornerLen, 0), handlePaint);
    canvas.drawLine(cropRect.bottomLeft, cropRect.bottomLeft - const Offset(0, cornerLen), handlePaint);
    // 右下
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight - const Offset(cornerLen, 0), handlePaint);
    canvas.drawLine(cropRect.bottomRight, cropRect.bottomRight - const Offset(0, cornerLen), handlePaint);

    // 6. 绘制四条边正中央的微型条状手柄（视觉提示用户边框支持单边拖拉）
    final edgeHandlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const edgeHandleLen = 14.0;
    // 上边中点
    canvas.drawLine(
      Offset(cropRect.center.dx - edgeHandleLen, cropRect.top),
      Offset(cropRect.center.dx + edgeHandleLen, cropRect.top),
      edgeHandlePaint,
    );
    // 下边中点
    canvas.drawLine(
      Offset(cropRect.center.dx - edgeHandleLen, cropRect.bottom),
      Offset(cropRect.center.dx + edgeHandleLen, cropRect.bottom),
      edgeHandlePaint,
    );
    // 左边中点
    canvas.drawLine(
      Offset(cropRect.left, cropRect.center.dy - edgeHandleLen),
      Offset(cropRect.left, cropRect.center.dy + edgeHandleLen),
      edgeHandlePaint,
    );
    // 右边中点
    canvas.drawLine(
      Offset(cropRect.right, cropRect.center.dy - edgeHandleLen),
      Offset(cropRect.right, cropRect.center.dy + edgeHandleLen),
      edgeHandlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.cropRect != cropRect ||
      oldDelegate.displayedRect != displayedRect ||
      oldDelegate.rotationAngle != rotationAngle;
}
