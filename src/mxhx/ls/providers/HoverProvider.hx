package mxhx.ls.providers;

import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.Hover;
import languageServerProtocol.Types.MarkupKind;
import languageServerProtocol.protocol.Protocol.HoverRequest;
import languageServerProtocol.protocol.Protocol.TextDocumentPositionParams;
import mxhx.ls.utils.MXHXDataUtils;
import mxhx.ls.utils.SymbolTextUtils;
import mxhx.resolver.IMXHXResolver;

using mxhx.ls.extensions.PositionExtensions;

class HoverProvider {
	private var resolver:IMXHXResolver;
	private var mxhxDataLookup:Map<String, IMXHXData>;
	private var sourceLookup:Map<String, String>;

	public function new(protocol:Protocol, resolver:IMXHXResolver, sourceLookup:Map<String, String>, mxhxDataLookup:Map<String, IMXHXData>) {
		this.resolver = resolver;
		this.sourceLookup = sourceLookup;
		this.mxhxDataLookup = mxhxDataLookup;

		protocol.onRequest(HoverRequest.type, onHover);
	}

	private function onHover(params:TextDocumentPositionParams, token:CancellationToken, resolve:Null<Hover>->Void, reject:ResponseError<NoData>->Void):Void {
		final uriAsString = params.textDocument.uri.toString();
		final mxhxData = mxhxDataLookup.get(uriAsString);
		if (mxhxData == null) {
			resolve(null);
			return;
		}
		final sourceCode = sourceLookup.get(uriAsString);
		if (sourceCode == null) {
			resolve(null);
			return;
		}
		final offset = params.position.toOffset(sourceCode);
		final tagData = mxhxData.findTagOrSurroundingTagContainingOffset(offset);
		if (tagData == null) {
			resolve(null);
			return;
		}

		if (MXHXDataUtils.isInsideTagPrefix(tagData, offset)) {
			if (tagData.uri != null && tagData.uri.length > 0) {
				// inside the prefix
				final prefix = tagData.prefix;
				var nsDeclaration = if (prefix.length > 0) {
					'```xml\nxmlns:${prefix}="${tagData.uri}"\n```';
				} else {
					'```xml\nxmlns="${tagData.uri}"\n```';
				}
				resolve({
					contents: {
						kind: MarkDown,
						value: nsDeclaration
					}
				});
				return;
			}
			resolve({
				contents: {
					kind: PlainText,
					value: 'Unknown namespace: ${tagData.prefix}'
				}
			});
			return;
		}

		final resolvedSymbol = MXHXDataUtils.getSymbolForMXHXNameAtOffset(tagData, offset, resolver);
		if (resolvedSymbol == null) {
			resolve(null);
			return;
		}

		var contents = SymbolTextUtils.symbolToDetail(resolvedSymbol);
		if (contents == null) {
			resolve(null);
			return;
		}
		contents = '```haxe\n${contents}\n```';
		if (resolvedSymbol.doc != null && resolvedSymbol.doc.length > 0) {
			contents += "\n\n---\n\n" + resolvedSymbol.doc;
			trace(resolvedSymbol.doc);
		}
		resolve({
			contents: {
				kind: MarkDown,
				value: contents
			}
		});
	}
}
