package mxhx.ls;

import mxhx.resolver.rtti.MXHXRttiResolver;
#if hxnodejs
import js.Node.process;
import jsonrpc.Protocol;
import jsonrpc.node.MessageReader;
import jsonrpc.node.MessageWriter;
import languageServerProtocol.protocol.Protocol.InitializeParams;
import mxhx.resolver.IMXHXResolver;

using mxhx.ls.extensions.DocumentUriExtensions;

class MXHXLanguageServer {
	public static function main():Void {
		haxe.Log.trace = function(v, ?i) {
			final r = [Std.string(v)];
			if (i != null && i.customParams != null) {
				for (v in i.customParams)
					r.push(Std.string(v));
			}
			process.stderr.write(r.join(",") + "\n");
		}

		final reader = new MessageReader(process.stdin);
		final writer = new MessageWriter(process.stdout);
		final languageServerProtocol = new Protocol(writer.write);
		final context = new Context(languageServerProtocol, onCreateResolver, onExit);
		reader.listen(languageServerProtocol.handleMessage);
	}

	private static function onExit():Void {
		process.exit();
	}

	private static function onCreateResolver(params:InitializeParams):IMXHXResolver {
		return new MXHXRttiResolver();
	}
}
#end
