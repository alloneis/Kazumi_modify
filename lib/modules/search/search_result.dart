import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/plugins.dart';

sealed class SearchResultBase {}

class BangumiSearchResult extends SearchResultBase {
  final BangumiItem item;
  BangumiSearchResult(this.item);
}

class PluginSearchResult extends SearchResultBase {
  final Plugin plugin;
  final SearchItem item;
  PluginSearchResult(this.plugin, this.item);

  BangumiItem toVirtualBangumiItem() {
    // Generate a deterministic ID based on the URL hash
    int virtualId = item.src.hashCode.abs();
    
    return BangumiItem(
      id: virtualId,
      type: 2, // Default to anime
      name: item.name,
      nameCn: item.name,
      summary: '源自插件: ${plugin.name}',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: {
        'large': '', // Plugins usually don't provide images in search results yet
        'common': '',
        'medium': '',
        'small': '',
        'grid': '',
      },
      tags: [],
      alias: [],
      ratingScore: 0.0,
      votes: 0,
      votesCount: [],
      info: '',
    );
  }

  Map<String, dynamic> toInfoRouteArguments() {
    return {
      'id': item.src.hashCode.abs(),
      'name': item.name,
      'nameCn': item.name,
      'summary': '源自插件: ${plugin.name}',
      'coverUrl': '',
      'images': {
        'large': '',
        'common': '',
        'medium': '',
        'small': '',
        'grid': '',
      },
      'isVirtual': true,
      'pluginName': plugin.name,
      'src': item.src,
    };
  }
}
