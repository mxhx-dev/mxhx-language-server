package mxhx.ls.utils;

import mxhx.resolver.IMXHXResolver;
import mxhx.symbols.IMXHXTypeSymbol;

class MXHXNamespaceUtils {
	private static final PREFIX_MX = "mx";
	private static final PREFIX_F = "f";
	private static final PREFIX_MC = "mc";
	private static final PREFIX_LOCAL = "local";
	private static final PREFIX_DEFAULT_NS = "ns";

	private static final URI_MXHX_2024_BASIC = "https://ns.mxhx.dev/2024/basic";
	private static final URI_MXHX_2024_FULL = "https://ns.mxhx.dev/2024/mxhx";
	private static final URI_FEATHERS_UI = "https://ns.feathersui.com/mxhx";
	private static final URI_MINIMALCOMPS = "https://ns.mxhx.dev/minimalcomps/mxhx";

	private static final URI_TO_PREFIX:Map<String, String> = [
		URI_MXHX_2024_BASIC => PREFIX_MX,
		URI_MXHX_2024_FULL => PREFIX_MX,
		URI_FEATHERS_UI => PREFIX_F,
		URI_MINIMALCOMPS => PREFIX_MC
	];

	private static final STAR = "*";
	private static final DOT_STAR = ".*";

	private static final DOMAIN_EREG = ~/^[a-z]+:\/\/(?:\w+\.)?(\w+)\.\w+\//;
	private static final DIGIT_EREG = ~/^[0-9]/;

	public static function getMXHXLanguageNamespace(tagData:IMXHXTagData):MXHXNamespace {
		var languageUri = getLanguageUriForTag(tagData);
		var prefixMap = tagData.compositePrefixMap;
		return getNamespaceFromURI(languageUri, prefixMap);
	}

	public static function getNamespaceFromURI(uri:String, prefixMap:PrefixMap):MXHXNamespace {
		if (uri == null) {
			return null;
		}
		if (prefixMap != null) {
			var uriPrefixes = prefixMap.getPrefixesForUri(uri);
			if (uriPrefixes.length > 0) {
				return new MXHXNamespace(uriPrefixes[0], uri);
			}
		}
		// we'll check if the namespace comes from a known library
		// with a common prefix
		var prefix = URI_TO_PREFIX.get(uri);
		if (prefix != null) {
			prefix = validatePrefix(prefix, prefixMap);
			if (prefix != null) {
				return new MXHXNamespace(prefix, uri);
			}
		}
		// try to guess a good prefix based on common formats
		if (DOMAIN_EREG.match(uri)) {
			var prefix = DOMAIN_EREG.matched(1);
			prefix = validatePrefix(prefix, prefixMap);
			if (prefix != null) {
				return new MXHXNamespace(prefix, uri);
			}
		}
		return null;
	}

	public static function getMXHXNamespaceForSymbol(symbol:IMXHXTypeSymbol, mxhxData:IMXHXData, resolver:IMXHXResolver):MXHXNamespace {
		// the prefix map may be null, if the file is empty
		var prefixMap = mxhxData.getPrefixMapForTag(mxhxData.rootTag);

		var tagNames = resolver.getTagNamesForQname(symbol.qname);
		var xmlUris:Array<String> = [];
		for (tagUri => tagName in tagNames) {
			// creating a new collection with only the namespace strings for easy
			// searching for other values
			xmlUris.push(tagUri);
		}

		// 1. try to use an existing xmlns with an uri
		if (prefixMap != null) {
			for (tagUri in xmlUris) {
				if (!isPreferredUri(tagUri, xmlUris, mxhxData)) {
					// skip namespaces that we'd rather not use in the current
					// context. for example, we prefer spark over mx, and this
					// class may be defined in both namespaces.
					continue;
				}
				var uriPrefixes = prefixMap.getPrefixesForUri(tagUri);
				if (uriPrefixes.length > 0) {
					var firstPrefix = uriPrefixes[0];
					return new MXHXNamespace(firstPrefix, tagUri);
				}
			}
		}

		// 2. try to use an existing xmlns with a package name
		var packageName = symbol.pack.join(".");
		var packageNamespace = getPackageNameMXHXNamespaceURI(packageName);
		if (prefixMap != null) {
			var packagePrefixes = prefixMap.getPrefixesForUri(packageNamespace);
			if (packagePrefixes.length > 0) {
				return new MXHXNamespace(packagePrefixes[0], packageNamespace);
			}
		}

		// 3. try to create a new xmlns with a prefix and uri

		// we're going to save our best option and keep trying to use it later
		// if the preferred prefix is already in use
		var fallbackNamespace:String = null;
		// we're searching again through the available namespaces. previously,
		// we looked for uris that were already used. now we want to find one
		// that hasn't been used yet
		for (tagUri in xmlUris) {
			if (!isPreferredUri(tagUri, xmlUris, mxhxData)) {
				// same as above, we should skip over certain namespaces when
				// there's a better option available.
				continue;
			}
			var uriPrefixes:Array<String> = null;
			if (prefixMap != null) {
				uriPrefixes = prefixMap.getPrefixesForUri(tagUri);
			}
			if (uriPrefixes == null || uriPrefixes.length == 0) {
				// we know this type is in one or more namespaces
				// let's try to figure out a nice prefix to use.
				// if we don't find our preferred prefix, we'll still
				// remember the uri for later.
				fallbackNamespace = tagUri;
				var resultNS = getNamespaceFromURI(fallbackNamespace, prefixMap);
				if (resultNS != null) {
					return resultNS;
				}
			}
		}

		if (fallbackNamespace != null) {
			// if we couldn't find a known prefix, use a numbered one
			var prefix = getNumberedNamespacePrefix(PREFIX_DEFAULT_NS, prefixMap);
			return new MXHXNamespace(prefix, fallbackNamespace);
		}

		// 4. special case: if the package namespace is simply *, try to use
		// local as the prefix, if it's not already defined. this matches the
		// behavior of Adobe Flash Builder.
		if (packageNamespace == STAR && (prefixMap == null || !prefixMap.containsPrefix(PREFIX_LOCAL))) {
			return new MXHXNamespace(PREFIX_LOCAL, packageNamespace);
		}

		// 5. try to use the final part of the package name as the prefix, if
		// it's not already defined.
		if (packageName != null && packageName.length > 0) {
			var parts = packageName.split(".");
			var finalPart = parts[parts.length - 1];
			if (prefixMap == null || !prefixMap.containsPrefix(finalPart)) {
				return new MXHXNamespace(finalPart, packageNamespace);
			}
		}

		// 6. worst case: create a new xmlns with numbered prefix and package name
		var prefix = getNumberedNamespacePrefix(PREFIX_DEFAULT_NS, prefixMap);
		return new MXHXNamespace(prefix, packageNamespace);
	}

	private static function validatePrefix(prefix:String, prefixMap:PrefixMap):String {
		if (prefix == null) {
			return null;
		}

		if (prefixMap != null && prefixMap.containsPrefix(prefix)) {
			// the prefix already exists with a different URI, so we can't
			// use it for this URI
			return null;
		}

		// prefixes shouldn't start with a number
		if (DIGIT_EREG.match(prefix.charAt(0))) {
			return null;
		}

		return prefix;
	}

	private static function getLanguageUriForTag(tagData:IMXHXTagData):String {
		var current = tagData;
		for (uri in tagData.compositePrefixMap.getAllUris()) {
			switch (uri) {
				case URI_MXHX_2024_FULL:
					return uri;
				case URI_MXHX_2024_BASIC:
					return uri;
				default:
			}
		}
		return null;
	}

	private static function isPreferredUri(tagUri:String, tagUris:Array<String>, mxmlData:IMXHXData):Bool {
		if (tagUri == URI_MXHX_2024_BASIC || tagUri == URI_MXHX_2024_FULL) {
			var rootTag = mxmlData.rootTag;
			if (rootTag != null) {
				var rootLanguageNamespace = getLanguageUriForTag(rootTag);
				if (rootLanguageNamespace != tagUri) {
					return false;
				}
			}
		}
		return true;
	}

	private static function getPackageNameMXHXNamespaceURI(packageName:String):String {
		if (packageName != null && packageName.length > 0) {
			return packageName + DOT_STAR;
		}
		return STAR;
	}

	private static function getNumberedNamespacePrefix(prefixPrefix:String, prefixMap:PrefixMap):String {
		// if all else fails, fall back to a generic namespace
		var count = 1;
		var prefix:String = null;
		do {
			prefix = prefixPrefix + count;
			if (prefixMap != null && prefixMap.containsPrefix(prefix)) {
				prefix = null;
			}
			count++;
		} while (prefix == null);
		return prefix;
	}
}
