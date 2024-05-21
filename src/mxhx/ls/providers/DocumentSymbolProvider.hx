package mxhx.ls.providers;

import mxhx.ls.utils.SymbolKindUtils;
import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.DocumentSymbol;
import languageServerProtocol.Types.SymbolInformation;
import languageServerProtocol.Types.SymbolKind;
import languageServerProtocol.protocol.Protocol.DocumentSymbolParams;
import languageServerProtocol.protocol.Protocol.DocumentSymbolRequest;
import mxhx.symbols.IMXHXFieldSymbol;
import mxhx.resolver.IMXHXResolver;
import mxhx.symbols.IMXHXTypeSymbol;

using mxhx.ls.extensions.PositionExtensions;

class DocumentSymbolProvider {
	private var resolver:IMXHXResolver;
	private var mxhxDataLookup:Map<String, IMXHXData>;
	private var sourceLookup:Map<String, String>;

	public function new(protocol:Protocol, resolver:IMXHXResolver, sourceLookup:Map<String, String>, mxhxDataLookup:Map<String, IMXHXData>) {
		this.resolver = resolver;
		this.sourceLookup = sourceLookup;
		this.mxhxDataLookup = mxhxDataLookup;

		protocol.onRequest(DocumentSymbolRequest.type, onDocumentSymbol);
	}

	private function onDocumentSymbol(params:DocumentSymbolParams, token:CancellationToken,
			resolve:Null<Array<EitherType<SymbolInformation, DocumentSymbol>>>->Void, reject:ResponseError<NoData>->Void):Void {
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
		var result:Array<DocumentSymbol> = [];
		parseTag(mxhxData.rootTag, result);
		resolve(result);
	}

	private function parseTag(tagData:IMXHXTagData, result:Array<DocumentSymbol>):Void {
		final resolvedSymbol = resolver.resolveTag(tagData);
		if (resolvedSymbol == null) {
			return;
		}
		var children:Array<DocumentSymbol> = [];
		var child = tagData.getFirstChildTag(true);
		while (child != null) {
			parseTag(child, children);
			child = child.getNextSiblingTag(true);
		}
		var documentSymbol:DocumentSymbol = {
			name: tagData.name,
			kind: SymbolKindUtils.symbolToSymbolKind(resolvedSymbol),
			range: {start: {line: tagData.line, character: tagData.column}, end: {line: tagData.endLine, character: tagData.endColumn}},
			selectionRange: {start: {line: tagData.line, character: tagData.column}, end: {line: tagData.endLine, character: tagData.endColumn}},
			children: children
		};
		if (resolvedSymbol is IMXHXTypeSymbol) {
			final idAttr = tagData.getAttributeData("id");
			if (idAttr != null) {
				documentSymbol.detail = 'id="${idAttr.rawValue}"';
			}
		}
		result.push(documentSymbol);
	}
}
