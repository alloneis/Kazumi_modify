import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/request/bangumi.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/modules/characters/character_item.dart';
import 'package:kazumi/modules/staff/staff_item.dart';

part 'info_controller.g.dart';

class InfoController = _InfoController with _$InfoController;

abstract class _InfoController with Store {
  final CollectController collectController = Modular.get<CollectController>();
  late BangumiItem bangumiItem;
  bool isVirtualBangumi = false;

  @observable
  bool isLoading = false;

  @observable
  var pluginSearchResponseList = ObservableList<PluginSearchResponse>();

  @observable
  var pluginSearchStatus = ObservableMap<String, String>();

  @observable
  var commentsList = ObservableList<CommentItem>();

  @observable
  var characterList = ObservableList<CharacterItem>();

  @observable
  var staffList = ObservableList<StaffFullItem>();

  void initBangumiItem(dynamic data) {
    if (data is BangumiItem) {
      bangumiItem = data;
      isVirtualBangumi = false;
      return;
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      isVirtualBangumi = map['isVirtual'] == true;
      bangumiItem = _fromMapToBangumiItem(map);
      return;
    }

    throw ArgumentError(
      'InfoController: unsupported bangumi payload type: ${data.runtimeType}',
    );
  }

  BangumiItem _fromMapToBangumiItem(Map<String, dynamic> data) {
    final dynamic rawId = data['id'];
    int parsedId = 0;
    if (rawId is int) {
      parsedId = rawId;
    } else if (rawId is String) {
      parsedId = int.tryParse(rawId) ?? 0;
    }
    if (parsedId == 0) {
      final String fallbackKey =
          (data['src'] ?? data['url'] ?? data['name'] ?? '').toString();
      parsedId = fallbackKey.isNotEmpty ? fallbackKey.hashCode.abs() : 0;
    }

    final String name = (data['name'] ?? '').toString();
    final String nameCn = (data['nameCn'] ?? data['name_cn'] ?? name).toString();
    final dynamic rawImages = data['images'];
    Map<String, String> images = {
      'large': '',
      'common': '',
      'medium': '',
      'small': '',
      'grid': '',
    };
    if (rawImages is Map) {
      images = rawImages.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      if ((images['large'] ?? '').isEmpty) {
        images['large'] = (data['coverUrl'] ?? '').toString();
      }
    } else {
      images['large'] = (data['coverUrl'] ?? '').toString();
    }

    return BangumiItem(
      id: parsedId,
      type: 2,
      name: name,
      nameCn: nameCn,
      summary: (data['summary'] ?? 'Plugin Search Result').toString(),
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: images,
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: (data['info'] ?? '').toString(),
    );
  }

  Future<void> queryBangumiInfoByID(int id, {String type = "init"}) async {
    isLoading = true;
    await BangumiHTTP.getBangumiInfoByID(id).then((value) {
      if (value != null) {
        if (type == "init") {
          bangumiItem = value;
        } else {
          bangumiItem.summary = value.summary;
          bangumiItem.tags = value.tags;
          bangumiItem.rank = value.rank;
          bangumiItem.airDate = value.airDate;
          bangumiItem.airWeekday = value.airWeekday;
          bangumiItem.alias = value.alias;
          bangumiItem.ratingScore = value.ratingScore;
          bangumiItem.votes = value.votes;
          bangumiItem.votesCount = value.votesCount;
        }
        collectController.updateLocalCollect(bangumiItem);
        isLoading = false;
      }
    });
  }

  Future<void> queryBangumiCommentsByID(int id, {int offset = 0}) async {
    if (offset == 0) {
      commentsList.clear();
    }
    await BangumiHTTP.getBangumiCommentsByID(id, offset: offset).then((value) {
      commentsList.addAll(value.commentList);
    });
    KazumiLogger().i('InfoController: loaded comments list length ${commentsList.length}');
  }

  Future<void> queryBangumiCharactersByID(int id) async {
    characterList.clear();
    await BangumiHTTP.getCharatersByBangumiID(id).then((value) {
      characterList.addAll(value.charactersList);
    });
    Map<String, int> relationValue = {
      '主角': 1,
      '配角': 2,
      '客串': 3,
    };

    try {
      characterList.sort((a, b) {
        int valueA = relationValue[a.relation] ?? 4;
        int valueB = relationValue[b.relation] ?? 4;
        return valueA.compareTo(valueB);
      });
    } catch (e) {
      KazumiDialog.showToast(message: '$e');
    }
    KazumiLogger().i('InfoController: loaded character list length ${characterList.length}');
  }

  Future<void> queryBangumiStaffsByID(int id) async {
    staffList.clear();
    await BangumiHTTP.getBangumiStaffByID(id).then((value) {
      staffList.addAll(value.data);
    });
    KazumiLogger().i('InfoController: loaded staff list length ${staffList.length}');
  }
}
