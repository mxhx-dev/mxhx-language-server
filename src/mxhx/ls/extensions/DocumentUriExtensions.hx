package mxhx.ls.extensions;

import languageServerProtocol.Types.DocumentUri;

using StringTools;

private final driveLetterPathRe = ~/^\/[a-zA-Z]:/;
private final uriRe = ~/^(([^:\/?#]+?):)?(\/\/([^\/?#]*))?([^?#]*)(\?([^#]*))?(#(.*))?/;

/** ported from VSCode sources **/
function toFsPath(uri:DocumentUri):String {
	if (!uriRe.match(uri.toString()) || uriRe.matched(2) != "file")
		throw 'Invalid uri: $uri';

	final path = uriRe.matched(5).urlDecode();
	if (driveLetterPathRe.match(path))
		return path.charAt(1).toLowerCase() + path.substr(2);
	else
		return path;
}

function isFile(uri:DocumentUri):Bool {
	return uri.toString().startsWith("file://");
}

function isUntitled(uri:DocumentUri):Bool {
	return uri.toString().startsWith("untitled:");
}

function isMXHXFile(uri:DocumentUri):Bool {
	return uri.toString().endsWith(".mxhx");
}
