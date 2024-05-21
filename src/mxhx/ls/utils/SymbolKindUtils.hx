package mxhx.ls.utils;

import mxhx.symbols.IMXHXFieldSymbol;
import languageServerProtocol.Types.SymbolKind;
import mxhx.symbols.IMXHXSymbol;
import mxhx.symbols.IMXHXEventSymbol;
import mxhx.symbols.IMXHXEnumFieldSymbol;
import mxhx.symbols.IMXHXAbstractSymbol;
import mxhx.symbols.IMXHXEnumSymbol;
import mxhx.symbols.IMXHXInterfaceSymbol;
import mxhx.symbols.IMXHXClassSymbol;
import languageServerProtocol.Types.CompletionItemKind;

class SymbolKindUtils {
	public static function symbolToSymbolKind(symbol:IMXHXSymbol):SymbolKind {
		if ((symbol is IMXHXClassSymbol)) {
			return Class;
		} else if ((symbol is IMXHXInterfaceSymbol)) {
			return Interface;
		} else if ((symbol is IMXHXAbstractSymbol)) {
			return Interface;
		} else if ((symbol is IMXHXEnumSymbol)) {
			return Enum;
		} else if ((symbol is IMXHXEnumFieldSymbol)) {
			return EnumMember;
		} else if ((symbol is IMXHXFieldSymbol)) {
			final fieldSymbol:IMXHXFieldSymbol = cast symbol;
			if (fieldSymbol.isMethod) {
				return Method;
			}
			return Field;
		} else if ((symbol is IMXHXEventSymbol)) {
			return Event;
		}
		return Object;
	}

	public static function symbolToCompletionItemKind(symbol:IMXHXSymbol):CompletionItemKind {
		if ((symbol is IMXHXClassSymbol)) {
			return Class;
		} else if ((symbol is IMXHXInterfaceSymbol)) {
			return Interface;
		} else if ((symbol is IMXHXAbstractSymbol)) {
			return Class;
		} else if ((symbol is IMXHXEnumSymbol)) {
			return Enum;
		} else if ((symbol is IMXHXEnumFieldSymbol)) {
			return EnumMember;
		} else if ((symbol is IMXHXFieldSymbol)) {
			final fieldSymbol:IMXHXFieldSymbol = cast symbol;
			if (fieldSymbol.isMethod) {
				return Method;
			}
			return Field;
		} else if ((symbol is IMXHXEventSymbol)) {
			return Event;
		}
		return Value;
	}
}
