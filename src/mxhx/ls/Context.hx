package mxhx.ls;

import jsonrpc.Protocol;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.DocumentUri;
import languageServerProtocol.protocol.Protocol.ClientCapabilities;
import languageServerProtocol.protocol.Protocol.DidChangeTextDocumentNotification;
import languageServerProtocol.protocol.Protocol.DidChangeTextDocumentParams;
import languageServerProtocol.protocol.Protocol.DidChangeWatchedFilesNotification;
import languageServerProtocol.protocol.Protocol.DidChangeWatchedFilesParams;
import languageServerProtocol.protocol.Protocol.DidCloseTextDocumentNotification;
import languageServerProtocol.protocol.Protocol.DidCloseTextDocumentParams;
import languageServerProtocol.protocol.Protocol.DidOpenTextDocumentNotification;
import languageServerProtocol.protocol.Protocol.DidOpenTextDocumentParams;
import languageServerProtocol.protocol.Protocol.DidSaveTextDocumentNotification;
import languageServerProtocol.protocol.Protocol.DidSaveTextDocumentParams;
import languageServerProtocol.protocol.Protocol.ExitNotification;
import languageServerProtocol.protocol.Protocol.InitializeParams;
import languageServerProtocol.protocol.Protocol.InitializeRequest;
import languageServerProtocol.protocol.Protocol.InitializeResult;
import languageServerProtocol.protocol.Protocol.ServerCapabilities;
import languageServerProtocol.protocol.Protocol.ShutdownRequest;
import languageServerProtocol.protocol.Protocol.TextDocumentSyncKind;
import mxhx.ls.providers.CompletionProvider;
import mxhx.ls.providers.DefinitionProvider;
import mxhx.ls.providers.DocumentSymbolProvider;
import mxhx.ls.providers.HoverProvider;
import mxhx.ls.providers.TypeDefinitionProvider;
import mxhx.parser.MXHXParser;
import mxhx.resolver.IMXHXResolver;

using mxhx.ls.extensions.DocumentUriExtensions;

class Context {
	private var protocol:Protocol;
	private var onCreateResolver:(InitializeParams) -> IMXHXResolver;
	private var onExit:() -> Void;
	private var clientCapabilities:ClientCapabilities;
	private var resolver:IMXHXResolver;
	private var sourceLookup:Map<String, String>;
	private var mxhxDataLookup:Map<String, IMXHXData>;

	public function new(protocol:Protocol, onCreateResolver:(InitializeParams) -> IMXHXResolver, onExit:() -> Void) {
		this.protocol = protocol;
		this.onCreateResolver = onCreateResolver;
		this.onExit = onExit;

		protocol.onRequest(InitializeRequest.type, onInitialize);
		protocol.onRequest(ShutdownRequest.type, onShutdown);
		protocol.onNotification(ExitNotification.type, (NoData) -> onExit());
		protocol.onNotification(DidOpenTextDocumentNotification.type, onDidOpenTextDocument);
		protocol.onNotification(DidChangeTextDocumentNotification.type, onDidChangeTextDocument);
		protocol.onNotification(DidCloseTextDocumentNotification.type, onDidCloseTextDocument);
		protocol.onNotification(DidSaveTextDocumentNotification.type, onDidSaveTextDocument);
		protocol.onNotification(DidChangeWatchedFilesNotification.type, onDidChangeWatchedFiles);
	}

	private function onInitialize(params:InitializeParams, _, resolve:InitializeResult->Void, _):Void {
		resolver = onCreateResolver(params);

		sourceLookup = [];
		mxhxDataLookup = [];

		clientCapabilities = params.capabilities;

		new CompletionProvider(protocol, resolver, sourceLookup, mxhxDataLookup,
			clientCapabilities?.textDocument?.completion?.completionItem?.snippetSupport ?? false, false);
		new HoverProvider(protocol, resolver, sourceLookup, mxhxDataLookup);
		new DefinitionProvider(protocol, resolver, sourceLookup, mxhxDataLookup);
		new DocumentSymbolProvider(protocol, resolver, sourceLookup, mxhxDataLookup);
		new TypeDefinitionProvider(protocol, resolver, sourceLookup, mxhxDataLookup);

		final serverCapabilities:ServerCapabilities = {
			textDocumentSync: TextDocumentSyncKind.Full,
			completionProvider: {
				triggerCharacters: [".", ":", " ", "<"],
			},
			definitionProvider: true,
			documentSymbolProvider: true,
			hoverProvider: true,
			typeDefinitionProvider: true,
		};
		resolve({capabilities: serverCapabilities});
	}

	private function onShutdown(_, _, resolve:NoData->Void, _) {
		return resolve(null);
	}

	private function isUriSupported(uri:DocumentUri):Bool {
		final uriAsString = uri.toString();
		if (!StringTools.startsWith(uriAsString, "file://")) {
			return false;
		}
		if (!StringTools.endsWith(uriAsString, ".mxhx")) {
			return false;
		}
		return true;
	}

	private function onDidOpenTextDocument(event:DidOpenTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (!isUriSupported(uri)) {
			return;
		}
		final uriAsString = uri.toString();
		final documentText = event.textDocument.text;
		sourceLookup.set(uriAsString, documentText);

		final parser = new MXHXParser(documentText, uriAsString);
		final mxhxData = parser.parse();
		mxhxDataLookup.set(uriAsString, mxhxData);
	}

	private function onDidChangeTextDocument(event:DidChangeTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (!isUriSupported(uri)) {
			return;
		}
		final uriAsString = uri.toString();
		final documentText = event.contentChanges[0].text;
		sourceLookup.set(uriAsString, documentText);

		final parser = new MXHXParser(documentText, uriAsString);
		final mxhxData = parser.parse();
		mxhxDataLookup.set(uriAsString, mxhxData);
	}

	private function onDidCloseTextDocument(event:DidCloseTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (!isUriSupported(uri)) {
			return;
		}
		final uriAsString = uri.toString();
		sourceLookup.remove(uriAsString);
		mxhxDataLookup.remove(uriAsString);
	}

	private function onDidSaveTextDocument(event:DidSaveTextDocumentParams) {
		final uri = event.textDocument.uri;
		if (!isUriSupported(uri)) {
			return;
		}
	}

	private function onDidChangeWatchedFiles(event:DidChangeWatchedFilesParams) {
		for (change in event.changes) {
			final uri = change.uri;
			if (!isUriSupported(uri)) {
				continue;
			}
			switch (change.type) {
				case Created:
				case Deleted:
				case Changed:
			}
		}
	}
}
