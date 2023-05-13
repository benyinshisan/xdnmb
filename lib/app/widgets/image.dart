import 'dart:typed_data';

import 'package:align_positioned/align_positioned.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:xdnmb_api/xdnmb_api.dart' hide Image;

import '../data/services/image.dart';
import '../data/services/persistent.dart';
import '../data/services/settings.dart';
import '../modules/image.dart';
import '../modules/paint.dart';
import '../modules/post_list.dart';
import '../routes/routes.dart';
import '../utils/extensions.dart';
import '../utils/image.dart';
import '../utils/navigation.dart';
import '../utils/toast.dart';
import 'dialog.dart';

class _RawThumbImage extends StatelessWidget {
  final String imageUrl;

  final String cacheKey;

  final ProgressIndicatorBuilder? progressIndicatorBuilder;

  final LoadingErrorWidgetBuilder? errorWidget;

  const _RawThumbImage(
      // ignore: unused_element
      {super.key,
      required this.imageUrl,
      required this.cacheKey,
      this.progressIndicatorBuilder,
      this.errorWidget});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: ThumbImage.minWidth,
            maxWidth: (constraints.maxWidth / 3.0)
                .clamp(ThumbImage.minWidth, ThumbImage.maxWidth),
            minHeight: ThumbImage.minHeight,
            maxHeight: ThumbImage.maxHeight,
          ),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            cacheKey: cacheKey,
            cacheManager: XdnmbImageCacheManager(),
            fit: BoxFit.contain,
            progressIndicatorBuilder: progressIndicatorBuilder,
            errorWidget: errorWidget,
          ),
        ),
      );
}

class _LargeImageDialog extends StatelessWidget {
  final PostBase post;

  final VoidCallback toImage;

  const _LargeImageDialog(
      // ignore: unused_element
      {super.key,
      required this.post,
      required this.toImage});

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.titleMedium;

    return SimpleDialog(
      children: [
        SimpleDialogOption(
          onPressed: () {
            postListBack();
            toImage();
          },
          child: Text('查看', style: textStyle),
        ),
        SimpleDialogOption(
          onPressed: () async {
            postListBack();
            await savePostImage(post);
          },
          child: Text('保存', style: textStyle),
        ),
        SimpleDialogOption(
          onPressed: () async {
            postListBack();
            final data = await loadImage(post);
            if (data != null) {
              await AppRoutes.toPaint(PaintController(data, false));
            }
          },
          child: Text('涂鸦', style: textStyle),
        ),
      ],
    );
  }
}

class _LargeImage extends StatelessWidget {
  final PostBase post;

  final VoidCallback toImage;

  // ignore: unused_element
  _LargeImage({super.key, required this.post, required this.toImage})
      : assert(post.hasImage);

  @override
  Widget build(BuildContext context) => CachedNetworkImage(
        imageUrl: post.imageUrl!,
        cacheKey: post.imageKey!,
        cacheManager: XdnmbImageCacheManager(),
        //fit: BoxFit.scaleDown,
        progressIndicatorBuilder: (context, url, progress) =>
            AlignPositioned.relative(
          alignment: Alignment.center,
          container: _RawThumbImage(
              imageUrl: post.thumbImageUrl!, cacheKey: post.thumbImageKey!),
          child: progress.progress != null
              ? CircularProgressIndicator(value: progress.progress)
              : const SizedBox.shrink(),
        ),
        errorWidget: (context, url, error) =>
            loadingImageErrorBuilder(context, url, error, showError: false),
        imageBuilder: (context, imageProvider) => Padding(
          padding: const EdgeInsets.only(bottom: 5.0),
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onLongPress: () => postListDialog(
                    _LargeImageDialog(post: post, toImage: toImage)),
                child: Image(image: imageProvider, fit: BoxFit.scaleDown),
              ),
            ),
          ),
        ),
      );
}

class ThumbImage extends StatefulWidget {
  static const double minWidth = 70.0;

  static const double maxWidth = 250.0;

  static const double minHeight = minWidth;

  static const double maxHeight = maxWidth;

  final PostBase post;

  final String? poUserHash;

  /// 涂鸦后调用，参数是图片数据
  final ValueSetter<Uint8List>? onPaintImage;

  final bool canReturnImageData;

  final bool allowShowLargeImageInPlace;

  ThumbImage(
      {super.key,
      required this.post,
      this.poUserHash,
      this.onPaintImage,
      this.canReturnImageData = false,
      this.allowShowLargeImageInPlace = true})
      : assert(post.hasImage);

  @override
  State<ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends State<ThumbImage> {
  final UniqueKey _heroTag = UniqueKey();

  bool _hasError = false;

  bool _isShowingLargeImage = false;

  double? _onTapAppBarHeight;

  double? _onTapScrollPosition;

  PostBase get _post => widget.post;

  Future<void> _toImage() async {
    final result = await AppRoutes.toImage(ImageController(
        heroTag: _heroTag,
        post: _post,
        poUserHash: widget.poUserHash,
        canReturnImageData: widget.canReturnImageData));
    if (widget.onPaintImage != null && result is Uint8List) {
      widget.onPaintImage!(result);
    }
  }

  void _setScrollPosition() {
    final controller = PostListController.get();
    final scrollController = controller.scrollController;
    if (scrollController != null) {
      _onTapAppBarHeight = controller.appBarHeight;
      _onTapScrollPosition = scrollController.position.pixels;
    }
  }

  double? _getOffset() {
    final renderBox = context.findRenderObject();
    if (renderBox != null) {
      final viewport = RenderAbstractViewport.of(renderBox);
      final offset = viewport.getOffsetToReveal(renderBox, 0.0);

      return offset.offset;
    }

    return null;
  }

  void _jumpToTopEdge() {
    final settings = SettingsService.to;

    var offset = _getOffset();
    if (offset != null) {
      final controller = PostListController.get();
      if (settings.autoHideAppBar) {
        offset -= controller.appBarHeight;
      }

      final scrollController = controller.scrollController;
      if (scrollController != null) {
        final position = scrollController.position;
        final pixels = position.pixels;
        var onTapPosition =
            (_onTapAppBarHeight != null && _onTapScrollPosition != null)
                ? (settings.autoHideAppBar
                    ? _onTapScrollPosition! + _onTapAppBarHeight!
                    : _onTapScrollPosition!)
                : null;
        if (onTapPosition != null &&
            onTapPosition > offset &&
            offset < pixels) {
          if (settings.autoHideAppBar) {
            onTapPosition -= controller.appBarHeight;
          }
          scrollController.jumpTo(onTapPosition.clamp(
              position.minScrollExtent, position.maxScrollExtent));
        } else if (offset < pixels) {
          scrollController.jumpTo(
              offset.clamp(position.minScrollExtent, position.maxScrollExtent));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.to;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () async {
        if (_isShowingLargeImage) {
          if (mounted) {
            _jumpToTopEdge();
            setState(() => _isShowingLargeImage = false);
          }
        } else if (widget.allowShowLargeImageInPlace &&
            settings.showLargeImageInPost) {
          if (mounted) {
            _setScrollPosition();
            setState(() => _isShowingLargeImage = true);
          }
        } else {
          await _toImage();
        }
      },
      child: Hero(
        tag: _heroTag,
        transitionOnUserGestures: true,
        child: _isShowingLargeImage
            ? _LargeImage(post: _post, toImage: _toImage)
            : _RawThumbImage(
                imageUrl: _hasError ? _post.imageUrl! : _post.thumbImageUrl!,
                cacheKey: _hasError ? _post.imageKey! : _post.thumbImageKey!,
                progressIndicatorBuilder: loadingThumbImageIndicatorBuilder,
                errorWidget: (context, url, error) {
                  // 因为部分GIF略缩图显示会出错，所以小图加载错误就加载大图
                  if (!_hasError) {
                    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                      if (mounted) {
                        setState(() => _hasError = true);
                      }
                    });
                  }

                  return _hasError
                      ? loadingImageErrorBuilder(context, url, error,
                          showError: false)
                      : const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}

Future<void> pickImage(ValueSetter<String> onPickImage) async {
  final data = PersistentDataService.to;
  final image = ImageService.to;

  if (image.hasStoragePermission && image.hasPhotoLibraryPermission) {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'xdnmb',
        initialDirectory: GetPlatform.isDesktop ? data.pictureDirectory : null,
        type: GetPlatform.isIOS ? FileType.image : FileType.custom,
        allowedExtensions:
            GetPlatform.isIOS ? null : ['gif', 'jpeg', 'jpg', 'png'],
        lockParentWindow: true,
      );

      if (result != null) {
        final path = result.files.single.path;
        if (path != null) {
          if (GetPlatform.isDesktop) {
            data.pictureDirectory = p.dirname(path);
          }
          onPickImage(path);
        } else {
          showToast('无法获取图片具体路径');
        }
      }
    } catch (e) {
      showToast('选取图片失败：$e');
    }
  } else {
    showToast('没有权限读取图片');
  }
}

class PickImage extends StatelessWidget {
  /// 选取图片后调用，参数为图片路径
  final ValueSetter<String> onPickImage;

  const PickImage({super.key, required this.onPickImage});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '加载图片',
        onPressed: () => pickImage(onPickImage),
        icon: const Icon(Icons.image),
      );
}
