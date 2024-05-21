package mxhx.ls.utils;

import mxhx.symbols.IMXHXEventSymbol;
import mxhx.symbols.IMXHXTypeSymbol;
import mxhx.symbols.IMXHXFieldSymbol;
import mxhx.symbols.IMXHXEnumSymbol;
import mxhx.symbols.IMXHXAbstractSymbol;
import mxhx.symbols.IMXHXInterfaceSymbol;
import mxhx.symbols.IMXHXClassSymbol;
import mxhx.symbols.IMXHXSymbol;

class SymbolTextUtils {
	public static function symbolToDetail(symbol:IMXHXSymbol):String {
		if ((symbol is IMXHXClassSymbol)) {
			final classSymbol:IMXHXClassSymbol = cast symbol;
			var classContents = 'class ${typeSymbolToNameWithParams(classSymbol)}';
			if (classSymbol.superClass != null) {
				classContents += ' extends ${typeSymbolToNameWithParams(classSymbol.superClass)}';
			}
			if (classSymbol.interfaces.length > 0) {
				classContents += " " + classSymbol.interfaces.map(interfaceSymbol -> 'implements ${typeSymbolToNameWithParams(interfaceSymbol)}').join(" ");
			}
			return classContents;
		} else if ((symbol is IMXHXInterfaceSymbol)) {
			final interfaceSymbol:IMXHXInterfaceSymbol = cast symbol;
			var interaceContents = 'interface ${typeSymbolToNameWithParams(interfaceSymbol)}';
			if (interfaceSymbol.interfaces.length > 0) {
				interaceContents += " "
					+ interfaceSymbol.interfaces.map(interfaceSymbol -> 'extends ${typeSymbolToNameWithParams(interfaceSymbol)}').join(" ");
			}
			return interaceContents;
		} else if ((symbol is IMXHXAbstractSymbol)) {
			final abstractSymbol:IMXHXAbstractSymbol = cast symbol;
			var abstractContents = 'abstract ${typeSymbolToNameWithParams(abstractSymbol)}';
			return abstractContents;
		} else if ((symbol is IMXHXEnumSymbol)) {
			final enumSymbol:IMXHXEnumSymbol = cast symbol;
			var enumContents = 'enum ${typeSymbolToNameWithParams(enumSymbol)}';
			enumContents;
		} else if ((symbol is IMXHXFieldSymbol)) {
			final fieldSymbol:IMXHXFieldSymbol = cast symbol;
			var fieldContents = '${fieldSymbol.isMethod ? "function" : "var"} ${fieldSymbol.name}:';
			fieldContents += fieldSymbol.type != null ? typeSymbolToNameWithParams(fieldSymbol.type) : "Dynamic";
			return fieldContents;
		} else if ((symbol is IMXHXEventSymbol)) {
			final eventSymbol:IMXHXEventSymbol = cast symbol;
			var eventContents = eventSymbol.type != null ? typeSymbolToNameWithParams(eventSymbol.type) : "Event";
			return eventContents;
		}
		return null;
	}

	private static function typeSymbolToNameWithParams(typeSymbol:IMXHXTypeSymbol):String {
		var result = typeSymbol.name;
		if (typeSymbol.params.length > 0) {
			result += "<";
			result += typeSymbol.params.map(p -> p != null ? typeSymbolToNameWithParams(p) : "?").join(", ");
			result += ">";
		}
		return result;
	}
}
