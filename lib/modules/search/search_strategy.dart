import 'package:kazumi/modules/search/search_result.dart';
import 'package:kazumi/request/bangumi.dart';
import 'package:kazumi/plugins/plugins.dart';

abstract class SearchStrategy {
  String get name;
  bool get supportsPagination;
  bool get supportsSortAndFilter;
  Future<List<SearchResultBase>> search(String keyword, {int offset = 0, String sort = 'heat', List<String> tags = const []});
}

class BangumiSearchStrategy extends SearchStrategy {
  @override
  String get name => 'Bangumi';
  
  @override
  bool get supportsPagination => true;
  
  @override
  bool get supportsSortAndFilter => true;

  @override
  Future<List<SearchResultBase>> search(String keyword, {int offset = 0, String sort = 'heat', List<String> tags = const []}) async {
    final items = await BangumiHTTP.bangumiSearch(keyword, offset: offset, sort: sort, tags: tags);
    return items.map((item) => BangumiSearchResult(item)).toList();
  }
}

class PluginSearchStrategy extends SearchStrategy {
  final Plugin plugin;
  
  PluginSearchStrategy(this.plugin);
  
  @override
  String get name => plugin.name;
  
  @override
  bool get supportsPagination => false; // Initial implementation without pagination
  
  @override
  bool get supportsSortAndFilter => false;

  @override
  Future<List<SearchResultBase>> search(String keyword, {int offset = 0, String sort = 'heat', List<String> tags = const []}) async {
    final response = await plugin.queryBangumi(keyword);
    return response.data.map((item) => PluginSearchResult(plugin, item)).toList();
  }
}
