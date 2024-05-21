package mxhx.ls.providers;

import js.html.URL;
import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Definition;
import languageServerProtocol.Types.DefinitionLink;
import languageServerProtocol.Types.DocumentUri;
import languageServerProtocol.protocol.Protocol.DefinitionParams;
import languageServerProtocol.protocol.Protocol.DefinitionRequest;
import mxhx.ls.utils.MXHXDataUtils;
import mxhx.resolver.IMXHXResolver;

using mxhx.ls.extensions.PositionExtensions;

class DefinitionProvider {
	private var resolver:IMXHXResolver;
	private var mxhxDataLookup:Map<String, IMXHXData>;
	private var sourceLookup:Map<String, String>;

	public function new(protocol:Protocol, resolver:IMXHXResolver, sourceLookup:Map<String, String>, mxhxDataLookup:Map<String, IMXHXData>) {
		this.resolver = resolver;
		this.sourceLookup = sourceLookup;
		this.mxhxDataLookup = mxhxDataLookup;

		protocol.onRequest(DefinitionRequest.type, onDefinition);
	}

	private function onDefinition(params:DefinitionParams, token:CancellationToken, resolve:Null<EitherType<Definition, DefinitionLink>>->Void,
			reject:ResponseError<NoData>->Void):Void {
		final uriAsString = params.textDocument.uri.toString();
		trace("definition: " + uriAsString);
		final mxhxData = mxhxDataLookup.get(uriAsString);
		if (mxhxData == null) {
			trace("no MXHX data: " + uriAsString);
			resolve(null);
			return;
		}
		final sourceCode = sourceLookup.get(uriAsString);
		if (sourceCode == null) {
			trace("no source code: " + uriAsString);
			resolve(null);
			return;
		}
		final offset = params.position.toOffset(sourceCode);
		final tagData = mxhxData.findTagOrSurroundingTagContainingOffset(offset);
		if (tagData == null) {
			trace("no tag data: " + uriAsString);
			resolve(null);
			return;
		}

		if (MXHXDataUtils.isInsideTagPrefix(tagData, offset)) {
			final rootTag = tagData.parent.rootTag;
			for (attributeData in rootTag.attributeData) {
				if (attributeData.prefix == "xmlns" && attributeData.shortName == tagData.prefix) {
					resolve({
						uri: params.textDocument.uri,
						range: {
							start: {line: attributeData.line, character: attributeData.column},
							end: {line: attributeData.endLine, character: attributeData.endColumn},
						}
					});
					return;
				}
			}
			resolve(null);
			return;
		}

		final resolvedSymbol = MXHXDataUtils.getSymbolForMXHXNameAtOffset(tagData, offset, resolver);
		if (resolvedSymbol == null) {
			trace("no resolved symbol: " + uriAsString);
			resolve(null);
			return;
		}
		trace("resolved symbol: " + resolvedSymbol.name);

		if (resolvedSymbol.file == null || resolvedSymbol.file.length == 0) {
			trace("no file: " + uriAsString);
			resolve(null);
			return;
		}

		final definitionUriAsString = Std.string(new URL('file:///${resolvedSymbol.file}'));
		final definitionDocumentUri = new DocumentUri(definitionUriAsString);
		var definitionSourceCode = sourceLookup.get(definitionUriAsString);
		if (definitionSourceCode == null) {
			try {
				definitionSourceCode = sys.io.File.getContent(resolvedSymbol.file);
			} catch (e:Dynamic) {
				resolve(null);
				return;
			}
		}
		if (definitionSourceCode != null) {
			final start = PositionExtensions.fromOffset(resolvedSymbol.offsets.start, definitionSourceCode);
			final end = PositionExtensions.fromOffset(resolvedSymbol.offsets.end, definitionSourceCode);
			final range = {
				start: start,
				end: end
			};
			resolve({
				uri: definitionDocumentUri,
				range: range
			});
		} else {
			resolve({
				uri: definitionDocumentUri,
				range: {
					start: {line: 0, character: 0},
					end: {line: 0, character: 0},
				}
			});
		}
	}
}
