import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/search/search_result.dart';
import 'package:kazumi/modules/search/search_strategy.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:mobx/mobx.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/utils/search_parser.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/repositories/collect_repository.dart';
import 'package:kazumi/repositories/search_history_repository.dart';
import 'package:kazumi/modules/collect/collect_type.dart';

part 'search_controller.g.dart';

class SearchPageController = _SearchPageController with _$SearchPageController;

abstract class _SearchPageController with Store {
  final _collectRepository = Modular.get<ICollectRepository>();
  final _searchHistoryRepository = Modular.get<ISearchHistoryRepository>();
  final _pluginsController = Modular.get<PluginsController>();

  @observable
  bool isLoading = false;

  @observable
  bool isTimeOut = false;

  @observable
  late bool notShowWatchedBangumis = _collectRepository.getSearchNotShowWatchedBangumis();

  @observable
  late bool notShowAbandonedBangumis = _collectRepository.getSearchNotShowAbandonedBangumis();

  @observable
  ObservableList<SearchResultBase> searchResults = ObservableList.of([]);

  @observable
  ObservableList<SearchStrategy> availableEngines = ObservableList.of([]);

  @observable
  SearchStrategy? currentEngine;

  @observable
  ObservableList<SearchHistory> searchHistories = ObservableList.of([]);

  void init() {
    availableEngines.clear();
    availableEngines.add(BangumiSearchStrategy());
    for (var plugin in _pluginsController.pluginList) {
      if (plugin.searchURL.isNotEmpty) {
        availableEngines.add(PluginSearchStrategy(plugin));
      }
    }
    currentEngine = availableEngines.first;
    loadSearchHistories();
  }

  @action
  void setCurrentEngine(SearchStrategy engine) {
    currentEngine = engine;
    searchResults.clear();
    isTimeOut = false;
  }

  @action
  void loadSearchHistories() {
    final histories = _searchHistoryRepository.getAllHistories();
    searchHistories.clear();
    searchHistories.addAll(histories);
  }

  String attachSortParams(String input, String sort) {
    SearchParser parser = SearchParser(input);
    String newInput = parser.updateSort(sort);
    return newInput;
  }

  @action
  Future<void> search(String input, {String type = 'add'}) async {
    if (currentEngine == null) return;

    if (type != 'add') {
      searchResults.clear();
      bool privateMode = _collectRepository.getPrivateMode();
      if (!privateMode) {
        if (_searchHistoryRepository.isHistoryFull(10)) {
          await _searchHistoryRepository.deleteOldest();
        }
        await _searchHistoryRepository.deleteDuplicates(input);
        await _searchHistoryRepository.saveHistory(input);
        loadSearchHistories();
      }
    }
    
    isLoading = true;
    isTimeOut = false;

    try {
      SearchParser parser = SearchParser(input);
      String? tag = parser.parseTag();
      String? sort = parser.parseSort();
      String keywords = parser.parseKeywords();

      final results = await currentEngine!.search(
        keywords,
        offset: searchResults.length,
        sort: sort ?? 'heat',
        tags: [if (tag != null) tag],
      );
      
      searchResults.addAll(results);
    } catch (_) {
      // Handle error
    } finally {
      isLoading = false;
      isTimeOut = searchResults.isEmpty;
    }
  }

  @action
  Future<void> deleteSearchHistory(SearchHistory history) async {
    await _searchHistoryRepository.deleteHistory(history);
    loadSearchHistories();
  }

  @action
  Future<void> clearSearchHistory() async {
    await _searchHistoryRepository.clearAllHistories();
    loadSearchHistories();
  }

  @action
  Future<void> setNotShowWatchedBangumis(bool value) async {
    notShowWatchedBangumis = value;
    await _collectRepository.updateSearchNotShowWatchedBangumis(value);
  }

  @action
  Future<void> setNotShowAbandonedBangumis(bool value) async {
    notShowAbandonedBangumis = value;
    await _collectRepository.updateSearchNotShowAbandonedBangumis(value);
  }

  Set<int> loadWatchedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.watched);
  }

  Set<int> loadAbandonedBangumiIds() {
    return _collectRepository.getBangumiIdsByType(CollectType.abandoned);
  }
}
