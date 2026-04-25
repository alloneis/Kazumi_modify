import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/request/request.dart';
import 'package:html/parser.dart';
import 'package:kazumi/request/api.dart';
import 'package:kazumi/utils/logger.dart';
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'package:kazumi/utils/utils.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/plugin_cookie_manager.dart';

/// Thrown by [Plugin.queryBangumi] when the response contains a CAPTCHA challenge
/// (i.e. the [AntiCrawlerConfig.captchaImage] XPath selector matches something
/// in the returned HTML).
class CaptchaRequiredException implements Exception {
  final String pluginName;
  const CaptchaRequiredException(this.pluginName);
  @override
  String toString() =>
      'CaptchaRequiredException: $pluginName requires captcha verification';
}

/// Thrown by [Plugin.queryBangumi] when the search request succeeds but the
/// XPath selectors return no results.
class NoResultException implements Exception {
  final String pluginName;
  const NoResultException(this.pluginName);
  @override
  String toString() =>
      'NoResultException: $pluginName returned no search results';
}

/// Thrown by [Plugin.queryBangumi] when the HTTP request or HTML parsing
/// fails for reasons other than a captcha challenge.
class SearchErrorException implements Exception {
  final String pluginName;
  final Object? cause;
  const SearchErrorException(this.pluginName, {this.cause});
  @override
  String toString() =>
      'SearchErrorException: $pluginName search failed${cause != null ? ' ($cause)' : ''}';
}

class Plugin {
  String api;
  String type;
  String name;
  String version;
  bool muliSources;
  bool useWebview;

  /// Deprecated (always true)
  bool useNativePlayer;
  bool usePost;
  bool useLegacyParser;
  bool adBlocker;
  String userAgent;
  String baseUrl;
  String searchURL;
  String searchList;
  String searchName;
  String searchResult;
  String chapterRoads;
  String chapterResult;
  String chapterName;
  String chapterUrl;
  String referer;
  AntiCrawlerConfig antiCrawlerConfig;

  Plugin({
    required this.api,
    required this.type,
    required this.name,
    required this.version,
    required this.muliSources,
    required this.useWebview,
    required this.useNativePlayer,
    required this.usePost,
    required this.useLegacyParser,
    required this.adBlocker,
    required this.userAgent,
    required this.baseUrl,
    required this.searchURL,
    required this.searchList,
    required this.searchName,
    required this.searchResult,
    required this.chapterRoads,
    required this.chapterResult,
    required this.chapterName,
    required this.chapterUrl,
    required this.referer,
    AntiCrawlerConfig? antiCrawlerConfig,
  }) : antiCrawlerConfig = antiCrawlerConfig ?? AntiCrawlerConfig.empty();

  factory Plugin.fromJson(Map<String, dynamic> json) {
    return Plugin(
      api: json['api'],
      type: json['type'],
      name: json['name'],
      version: json['version'],
      muliSources: json['muliSources'],
      useWebview: json['useWebview'],
      useNativePlayer: json['useNativePlayer'],
      usePost: json['usePost'] ?? false,
      useLegacyParser: json['useLegacyParser'] ?? false,
      adBlocker: json['adBlocker'] ?? false,
      userAgent: json['userAgent'],
      baseUrl: json['baseURL'],
      searchURL: json['searchURL'],
      searchList: json['searchList'],
      searchName: json['searchName'],
      searchResult: json['searchResult'],
      chapterRoads: json['chapterRoads'],
      chapterResult: json['chapterResult'] ?? '',
      chapterName: json['chapterName'] ?? '',
      chapterUrl: json['chapterUrl'] ?? '',
      referer: json['referer'] ?? '',
      antiCrawlerConfig: json['antiCrawlerConfig'] != null
          ? AntiCrawlerConfig.fromJson(
              Map<String, dynamic>.from(json['antiCrawlerConfig']),
            )
          : AntiCrawlerConfig.empty(),
    );
  }

  factory Plugin.fromTemplate() {
    return Plugin(
      api: Api.apiLevel.toString(),
      type: 'anime',
      name: '',
      version: '',
      muliSources: true,
      useWebview: true,
      useNativePlayer: true,
      usePost: false,
      useLegacyParser: false,
      adBlocker: false,
      userAgent: '',
      baseUrl: '',
      searchURL: '',
      searchList: '',
      searchName: '',
      searchResult: '',
      chapterRoads: '',
      chapterResult: '',
      chapterName: '',
      chapterUrl: '',
      referer: '',
      antiCrawlerConfig: AntiCrawlerConfig.empty(),
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data['api'] = api;
    data['type'] = type;
    data['name'] = name;
    data['version'] = version;
    data['muliSources'] = muliSources;
    data['useWebview'] = useWebview;
    data['useNativePlayer'] = useNativePlayer;
    data['usePost'] = usePost;
    data['useLegacyParser'] = useLegacyParser;
    data['adBlocker'] = adBlocker;
    data['userAgent'] = userAgent;
    data['baseURL'] = baseUrl;
    data['searchURL'] = searchURL;
    data['searchList'] = searchList;
    data['searchName'] = searchName;
    data['searchResult'] = searchResult;
    data['chapterRoads'] = chapterRoads;
    data['chapterResult'] = chapterResult;
    data['chapterName'] = chapterName;
    data['chapterUrl'] = chapterUrl;
    data['referer'] = referer;
    data['antiCrawlerConfig'] = antiCrawlerConfig.toJson();
    return data;
  }

  bool get hasAdvancedChapterSelectors =>
      chapterName.trim().isNotEmpty && chapterUrl.trim().isNotEmpty;

  bool get hasBuiltInChapterResolver {
    final Uri? uri = Uri.tryParse(baseUrl);
    return chapterRoads.trim().isNotEmpty ||
        (uri != null && _looksLikeIkanbotBaseUri(uri.resolve('/play/0')));
  }

  static const List<String> _resourceUrlAttributes = <String>[
    'href',
    'udata',
    'data-href',
    'data-url',
    'data-src',
    'src',
  ];

  String _extractResourceUrl(dynamic node) {
    final Map<String, String> attributes = _stringifyAttributes(node);
    for (final String attribute in _resourceUrlAttributes) {
      final String candidate = (attributes[attribute] ?? '').trim();
      if (_isUsableResourceUrl(candidate)) {
        return candidate;
      }
    }

    try {
      final children = node.children;
      if (children is Iterable) {
        for (final dynamic child in children) {
          final String tagName =
              '${child.localName ?? child.nodeName ?? ''}'.toLowerCase();
          if (tagName != 'udata') {
            continue;
          }

          final Map<String, String> childAttributes = _stringifyAttributes(
            child,
          );
          for (final String attribute in <String>[
            ..._resourceUrlAttributes,
            'value',
            'url',
          ]) {
            final String candidate = (childAttributes[attribute] ?? '').trim();
            if (_isUsableResourceUrl(candidate)) {
              return candidate;
            }
          }

          final String childText = (child.text ?? '').trim();
          if (_isUsableResourceUrl(childText)) {
            return childText;
          }
        }
      }
    } catch (_) {}

    return '';
  }

  Map<String, String> _stringifyAttributes(dynamic node) {
    try {
      final attributes = node.attributes;
      if (attributes is Map) {
        return attributes.map(
          (dynamic key, dynamic value) =>
              MapEntry(key.toString(), value?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return const <String, String>{};
  }

  bool _isUsableResourceUrl(String value) {
    if (value.isEmpty) return false;
    final String normalized = value.trim().toLowerCase();
    return normalized != '#' && !normalized.startsWith('javascript:');
  }

  String _normalizeChapterName(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').trim();
  }


  bool _looksLikeIkanbotBaseUri(Uri? uri) {
    if (uri == null) {
      return false;
    }
    return uri.host.contains('ikanbot.com');
  }

  bool _looksLikeIkanbotPlayPage(String html) {
    return _extractIkanbotInputValueFromHtml(html, 'current_id').isNotEmpty &&
        _extractIkanbotInputValueFromHtml(html, 'mtype').isNotEmpty &&
        _extractIkanbotInputValueFromHtml(html, 'e_token').isNotEmpty;
  }

  String _extractIkanbotInputValueFromHtml(String html, String inputId) {
    if (html.isEmpty) return '';
    final RegExp directPattern = RegExp(
      '<input[^>]*\\bid="$inputId"[^>]*\\bvalue="([^"]*)"',
      caseSensitive: false,
    );
    final RegExp reversePattern = RegExp(
      '<input[^>]*\\bvalue="([^"]*)"[^>]*\\bid="$inputId"',
      caseSensitive: false,
    );

    final RegExpMatch? directMatch = directPattern.firstMatch(html);
    if (directMatch != null) {
      return (directMatch.group(1) ?? '').trim();
    }

    final RegExpMatch? reverseMatch = reversePattern.firstMatch(html);
    if (reverseMatch != null) {
      return (reverseMatch.group(1) ?? '').trim();
    }

    return '';
  }

  String _generateIkanbotToken(String currentId, String eToken) {
    if (currentId.isEmpty || eToken.isEmpty || currentId.length < 4) {
      return '';
    }

    final String last4Chars = currentId.substring(currentId.length - 4);
    final List<String> result = <String>[];
    String remainingToken = eToken;

    for (final String digit in last4Chars.split('')) {
      final int? num = int.tryParse(digit);
      if (num == null) {
        return '';
      }
      final int offset = (num % 3) + 1;
      if (remainingToken.length < offset + 8) {
        return '';
      }
      result.add(remainingToken.substring(offset, offset + 8));
      remainingToken = remainingToken.substring(offset + 8);
    }

    return result.join('');
  }

  Future<List<Road>> _queryIkanbotChapterRoads(
    Uri? pageUri,
    String htmlString, {
    CancelToken? cancelToken,
  }) async {
    final String currentId = _extractIkanbotInputValueFromHtml(
      htmlString,
      'current_id',
    );
    final String mtype = _extractIkanbotInputValueFromHtml(
      htmlString,
      'mtype',
    );
    final String eToken = _extractIkanbotInputValueFromHtml(
      htmlString,
      'e_token',
    );
    final String token = _generateIkanbotToken(currentId, eToken);

    KazumiLogger().w(
      'Plugin: $name Ikanbot params extracted '
      '(currentId: ${currentId.isNotEmpty}, mtype: ${mtype.isNotEmpty}, '
      'eToken: ${eToken.isNotEmpty}, token: ${token.isNotEmpty})',
      forceLog: true,
    );
    if (currentId.isEmpty || mtype.isEmpty || token.isEmpty) {
      KazumiLogger().w(
        'Plugin: $name Ikanbot chapter API params missing '
        '(currentId: ${currentId.isNotEmpty}, mtype: ${mtype.isNotEmpty}, token: ${token.isNotEmpty})',
        forceLog: true,
      );
      return <Road>[];
    }

    final Uri apiUri = Uri.parse('https://v.ikanbot.com/api/getResN');
    final String cookieHeader = await _cookieHeaderFor(apiUri.toString());
    final Map<String, String> httpHeaders = <String, String>{
      'referer': pageUri != null
          ? '${pageUri.scheme}://${pageUri.host}/'
          : '$baseUrl/',
      'Accept-Language': Utils.getRandomAcceptedLanguage(),
      'Connection': 'keep-alive',
      if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
    };

    KazumiLogger().w(
      'Plugin: $name sending Ikanbot getResN request '
      '(videoId: $currentId, mtype: $mtype, token: ${token.isNotEmpty})',
      forceLog: true,
    );
    final Response resp = await Request().get(
      apiUri.toString(),
      data: <String, String>{
        'videoId': currentId,
        'mtype': mtype,
        'token': token,
      },
      options: Options(headers: httpHeaders),
      cancelToken: cancelToken,
    );

    final dynamic responseData =
        resp.data is String ? jsonDecode(resp.data) : resp.data;
    if (responseData is! Map || responseData['state'] != 1) {
      KazumiLogger().w(
        'Plugin: $name Ikanbot chapter API returned invalid state: '
        '${responseData is Map ? responseData['state'] : responseData.runtimeType}',
        forceLog: true,
      );
      return <Road>[];
    }

    final dynamic listData = responseData['data']?['list'];
    if (listData is! List || listData.isEmpty) {
      return <Road>[];
    }

    final bool preferNewName = mtype == '1';
    final List<Road> roads = <Road>[];
    int count = 1;

    for (final dynamic item in listData.take(1)) {
      final dynamic rawResData = item is Map ? item['resData'] : null;
      if (rawResData is! String || rawResData.isEmpty) {
        continue;
      }

      dynamic parsedResData;
      try {
        parsedResData = jsonDecode(rawResData);
      } catch (_) {
        continue;
      }
      if (parsedResData is! List) {
        continue;
      }

      final List<String> chapterUrlList = <String>[];
      final List<String> chapterNameList = <String>[];

      for (final dynamic resItem in parsedResData) {
        if (resItem is! Map) {
          continue;
        }

        final String lineUrlData = (resItem['url'] ?? '').toString().trim();
        final String newName = (resItem['newName'] ?? '').toString().trim();
        if (lineUrlData.isEmpty) {
          continue;
        }

        for (final String urlEntry in lineUrlData.split('#')) {
          final List<String> urlParts = urlEntry.split(r'$');
          if (urlParts.length < 2) {
            continue;
          }

          String urlName = urlParts[0].trim();
          final String urlLink = urlParts[1].trim();
          if (preferNewName &&
              newName.isNotEmpty &&
              int.tryParse(newName) == null) {
            urlName = newName;
          }

          final String normalizedName = _normalizeChapterName(urlName);
          if (normalizedName.isEmpty ||
              urlLink.isEmpty ||
              !urlLink.toLowerCase().endsWith('m3u8')) {
            continue;
          }

          chapterUrlList.add(urlLink);
          chapterNameList.add(normalizedName);
        }
      }

      if (chapterUrlList.isEmpty || chapterNameList.isEmpty) {
        continue;
      }

      roads.add(
        Road(
          name: '播放列表$count',
          data: chapterUrlList,
          identifier: chapterNameList,
        ),
      );
      count++;
    }

    KazumiLogger().w(
      'Plugin: $name Ikanbot chapter API resolved ${roads.length} roads',
      forceLog: true,
    );
    return roads;
  }

  List<String> _extractXPathValues(
    dynamic element,
    String xpath, {
    bool normalizeChapterName = false,
    bool resourceUrl = false,
  }) {
    if (xpath.trim().isEmpty) {
      return const <String>[];
    }

    dynamic result;
    try {
      result = element.queryXPath(xpath);
    } catch (_) {
      return const <String>[];
    }
    final List<String> values = [];
    final bool hasAttrValues = result.attrs.isNotEmpty;

    if (hasAttrValues) {
      for (final String? attr in result.attrs) {
        final String value = normalizeChapterName
            ? _normalizeChapterName(attr ?? '')
            : (attr ?? '').trim();
        if (resourceUrl) {
          if (_isUsableResourceUrl(value)) {
            values.add(value);
          }
        } else if (value.isNotEmpty) {
          values.add(value);
        }
      }
      return values;
    }

    for (final item in result.nodes) {
      final String value = resourceUrl
          ? _extractResourceUrl(item.node)
          : normalizeChapterName
              ? _normalizeChapterName(item.node.text ?? '')
              : (item.node.text ?? '').trim();
      if (resourceUrl) {
        if (_isUsableResourceUrl(value)) {
          values.add(value);
        }
      } else if (value.isNotEmpty) {
        values.add(value);
      }
    }
    return values;
  }

  Future<PluginSearchResponse> queryBangumi(
    String keyword, {
    bool shouldRethrow = false,
  }) async {
    try {
      String queryURL = searchURL.replaceAll(
        '@keyword',
        Uri.encodeQueryComponent(keyword),
      );
      dynamic resp;
      List<SearchItem> searchItems = [];
      final String cookieHeader = await _cookieHeaderFor(queryURL);
      if (usePost) {
        Uri uri = Uri.parse(queryURL);
        Map<String, String> queryParams = uri.queryParameters;
        Uri postUri = Uri(scheme: uri.scheme, host: uri.host, path: uri.path);
        var httpHeaders = {
          'referer': '$baseUrl/',
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept-Language': Utils.getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        };
        resp = await Request().post(
          postUri.toString(),
          options: Options(headers: httpHeaders),
          extra: {'customError': ''},
          data: queryParams,
          shouldRethrow: shouldRethrow,
        );
      } else {
        var httpHeaders = {
          'referer': '$baseUrl/',
          'Accept-Language': Utils.getRandomAcceptedLanguage(),
          'Connection': 'keep-alive',
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
        };
        resp = await Request().get(
          queryURL,
          options: Options(headers: httpHeaders),
          shouldRethrow: shouldRethrow,
          extra: {'customError': ''},
        );
      }

      var htmlString = resp.data.toString();
      var htmlElement = parse(htmlString).documentElement!;

      // Detect captcha challenge: if antiCrawlerConfig is enabled, check both
      // captchaImage and captchaButton XPaths 鈥?if either matches, throw so
      // callers can show the dedicated captcha UI instead of a generic error.
      if (antiCrawlerConfig.enabled) {
        final List<String> detectionXpaths = [
          antiCrawlerConfig.captchaImage,
          antiCrawlerConfig.captchaButton,
        ].where((x) => x.isNotEmpty).toList();
        final bool captchaDetected = detectionXpaths.any(
          (xpath) => htmlElement.queryXPath(xpath).node != null,
        );
        if (captchaDetected) {
          KazumiLogger().w(
            'Plugin: $name detected captcha challenge in search response',
          );
          throw CaptchaRequiredException(name);
        }
      }

      htmlElement.queryXPath(searchList).nodes.forEach((element) {
        try {
          final dynamic resultNode = element.queryXPath(searchResult).node;
          final String itemUrl = _extractResourceUrl(resultNode);
          if (itemUrl.isEmpty) {
            return;
          }
          SearchItem searchItem = SearchItem(
            name: element.queryXPath(searchName).node!.text?.trim() ?? '',
            src: itemUrl,
          );
          searchItems.add(searchItem);
          KazumiLogger().i(
            'Plugin: $name ${element.queryXPath(searchName).node!.text ?? ''} $baseUrl$itemUrl',
          );
        } catch (_) {}
      });
      if (searchItems.isEmpty) throw NoResultException(name);
      return PluginSearchResponse(pluginName: name, data: searchItems);
    } on CaptchaRequiredException {
      rethrow;
    } on NoResultException {
      rethrow;
    } catch (e, st) {
      KazumiLogger().w('Plugin: $name search failed', error: e, stackTrace: st);
      if (shouldRethrow) throw SearchErrorException(name, cause: e);
      return PluginSearchResponse(pluginName: name, data: []);
    }
  }

  Future<List<Road>> querychapterRoads(
    String url, {
    CancelToken? cancelToken,
  }) async {
    List<Road> roadList = [];
    if (!url.contains('https')) {
      url = url.replaceAll('http', 'https');
    }
    String queryURL = '';
    if (url.contains(baseUrl)) {
      queryURL = url;
    } else {
      queryURL = baseUrl + url;
    }
    var httpHeaders = {
      'referer': '$baseUrl/',
      'Accept-Language': Utils.getRandomAcceptedLanguage(),
      'Connection': 'keep-alive',
    };
    try {
      var resp = await Request().get(
        queryURL,
        options: Options(headers: httpHeaders),
        cancelToken: cancelToken,
      );
      var htmlString = resp.data.toString();
      final document = parse(htmlString);
      final htmlElement = document.documentElement;
      if (htmlElement == null) {
        KazumiLogger().w(
          'Plugin: $name chapter page parse failed (documentElement is null) for $queryURL',
          forceLog: true,
        );
        return roadList;
      }
      final Uri? pageUri = Uri.tryParse(queryURL);
      final bool hasIkanbotInputs = _looksLikeIkanbotPlayPage(htmlString);
      final bool hasCurrentIdInput =
          _extractIkanbotInputValueFromHtml(htmlString, 'current_id').isNotEmpty;
      final bool hasMtypeInput =
          _extractIkanbotInputValueFromHtml(htmlString, 'mtype').isNotEmpty;
      final bool hasETokenInput =
          _extractIkanbotInputValueFromHtml(htmlString, 'e_token').isNotEmpty;
      KazumiLogger().w(
        'Plugin: $name chapter page probe '
        '(url: $queryURL, ikanbotInputs: $hasIkanbotInputs, '
        'currentId: $hasCurrentIdInput, mtype: $hasMtypeInput, eToken: $hasETokenInput)',
        forceLog: true,
      );
      if (hasIkanbotInputs) {
        final List<Road> ikanbotRoads = await _queryIkanbotChapterRoads(
          pageUri,
          htmlString,
          cancelToken: cancelToken,
        );
        if (ikanbotRoads.isNotEmpty) {
          return ikanbotRoads;
        }
      }
      int count = 1;
      htmlElement.queryXPath(chapterRoads).nodes.forEach((element) {
        try {
          List<String> chapterUrlList = [];
          List<String> chapterNameList = [];
          if (hasAdvancedChapterSelectors) {
            final List<String> rawChapterUrlList = _extractXPathValues(
              element,
              chapterUrl,
              resourceUrl: true,
            );
            final List<String> rawChapterNameList = _extractXPathValues(
              element,
              chapterName,
              normalizeChapterName: true,
            );
            final int chapterCount =
                rawChapterUrlList.length < rawChapterNameList.length
                    ? rawChapterUrlList.length
                    : rawChapterNameList.length;
            chapterUrlList = rawChapterUrlList.take(chapterCount).toList();
            chapterNameList = rawChapterNameList.take(chapterCount).toList();
          } else {
            element.queryXPath(chapterResult).nodes.forEach((item) {
              final String itemUrl = _extractResourceUrl(item.node);
              final String itemName = _normalizeChapterName(
                item.node.text ?? '',
              );
              if (itemUrl.isEmpty || itemName.isEmpty) {
                return;
              }
              chapterUrlList.add(itemUrl);
              chapterNameList.add(itemName);
            });
          }
          if (chapterUrlList.isNotEmpty && chapterNameList.isNotEmpty) {
            Road road = Road(
              name: '播放列表$count',
              data: chapterUrlList,
              identifier: chapterNameList,
            );
            roadList.add(road);
            count++;
          }
        } catch (_) {}
      });
    } catch (e, st) {
      KazumiLogger().w(
        'Plugin: $name chapter query failed for $queryURL',
        error: e,
        stackTrace: st,
        forceLog: true,
      );
    }
    return roadList;
  }

  Future<String> testSearchRequest(
    String keyword, {
    bool shouldRethrow = false,
    CancelToken? cancelToken,
  }) async {
    String queryURL = searchURL.replaceAll(
      '@keyword',
      Uri.encodeQueryComponent(keyword),
    );
    dynamic resp;
    if (usePost) {
      Uri uri = Uri.parse(queryURL);
      Map<String, String> queryParams = uri.queryParameters;
      Uri postUri = Uri(scheme: uri.scheme, host: uri.host, path: uri.path);
      var httpHeaders = {
        'referer': '$baseUrl/',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept-Language': Utils.getRandomAcceptedLanguage(),
        'Connection': 'keep-alive',
      };
      resp = await Request().post(
        postUri.toString(),
        options: Options(headers: httpHeaders),
        extra: {'customError': ''},
        data: queryParams,
        shouldRethrow: shouldRethrow,
        cancelToken: cancelToken,
      );
    } else {
      var httpHeaders = {
        'referer': '$baseUrl/',
        'Accept-Language': Utils.getRandomAcceptedLanguage(),
        'Connection': 'keep-alive',
      };
      resp = await Request().get(
        queryURL,
        options: Options(headers: httpHeaders),
        shouldRethrow: shouldRethrow,
        extra: {'customError': ''},
        cancelToken: cancelToken,
      );
    }

    return resp.data.toString();
  }

  Future<String> _cookieHeaderFor(String url) async {
    if (!PluginCookieManager.instance.hasCookies(name)) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    try {
      final cookies =
          await PluginCookieManager.instance.getJar(name).loadForRequest(uri);
      if (cookies.isEmpty) return '';
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  String buildFullUrl(String urlItem) {
    if (urlItem.contains(baseUrl) ||
        urlItem.contains(baseUrl.replaceAll('https', 'http'))) {
      return urlItem;
    }
    return baseUrl + urlItem;
  }

  Map<String, String> buildHttpHeaders() {
    return {
      'user-agent': userAgent.isEmpty ? Utils.getRandomUA() : userAgent,
      if (referer.isNotEmpty) 'referer': referer,
    };
  }

  PluginSearchResponse testQueryBangumi(String htmlString) {
    List<SearchItem> searchItems = [];
    var htmlElement = parse(htmlString).documentElement!;
    htmlElement.queryXPath(searchList).nodes.forEach((element) {
      try {
        SearchItem searchItem = SearchItem(
          name: element.queryXPath(searchName).node!.text?.trim() ?? '',
          src: element.queryXPath(searchResult).node!.attributes['href'] ?? '',
        );
        searchItems.add(searchItem);
        KazumiLogger().i(
          'Plugin: $name ${element.queryXPath(searchName).node!.text ?? ''} $baseUrl${element.queryXPath(searchResult).node!.attributes['href'] ?? ''}',
        );
      } catch (_) {}
    });
    PluginSearchResponse pluginSearchResponse = PluginSearchResponse(
      pluginName: name,
      data: searchItems,
    );
    return pluginSearchResponse;
  }
}




