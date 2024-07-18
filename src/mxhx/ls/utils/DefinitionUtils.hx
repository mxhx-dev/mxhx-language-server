package mxhx.ls.utils;

import mxhx.symbols.IMXHXClassSymbol;
import mxhx.symbols.IMXHXInterfaceSymbol;
import mxhx.symbols.IMXHXTypeSymbol;

class DefinitionUtils {
	public static function extendsOrImplements(typeSymbol:IMXHXTypeSymbol, qualifiedNameToFind:String):Bool {
		if ((typeSymbol is IMXHXClassSymbol)) {
			var classSymbol:IMXHXClassSymbol = cast typeSymbol;
			var current = classSymbol;
			while (current != null) {
				if (current.qname == qualifiedNameToFind) {
					return true;
				}
				current = current.superClass;
			}
			for (current in classSymbol.interfaces) {
				if (current.qname == qualifiedNameToFind) {
					return true;
				}
			}
		} else if ((typeSymbol is IMXHXInterfaceSymbol)) {
			var interfaceSymbol:IMXHXInterfaceSymbol = cast typeSymbol;
			if (interfaceSymbol.qname == qualifiedNameToFind) {
				return true;
			}
			for (current in interfaceSymbol.interfaces) {
				if (current.qname == qualifiedNameToFind) {
					return true;
				}
			}
		}
		return false;
	}
}
