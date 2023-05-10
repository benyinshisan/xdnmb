import 'dart:io';
import 'dart:math';

import 'package:isar/isar.dart';
import 'package:path/path.dart';

import '../data/models/history.dart';
import '../data/models/post.dart';
import '../data/models/reference.dart';
import '../data/models/reply.dart';
import '../data/models/tagged_post.dart';
import 'directory.dart';

/// 由于兼容原因，isar数据库名字为`history`
const String _databaseName = 'history';

const List<CollectionSchema<dynamic>> _isarSchemas = [
  BrowseHistorySchema,
  PostDataSchema,
  ReplyDataSchema,
  ReferenceDataSchema,
  TaggedPostSchema,
];

/// [Isar]实例只能同时存在一个
late final Isar isar;

/// 注意iOS设备可能内存不足
Future<void> initIsar() async {
  final databaseFile = File(join(databasePath, '$_databaseName.isar'));
  // 默认256MB大小，保留至少100MB左右的空间
  final maxSizeMiB = await databaseFile.exists()
      ? ((await databaseFile.length() / (1024 * 1024)).floor() + 100)
      : 256;

  isar = await Isar.open(_isarSchemas,
      directory: databasePath,
      name: _databaseName,
      maxSizeMiB: max(maxSizeMiB, 256),
      inspector: false);
}
