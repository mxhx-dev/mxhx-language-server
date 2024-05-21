package mxhx.ls.providers;

import languageServerProtocol.Types.CompletionItemKind;
import mxhx.ls.utils.SymbolTextUtils;
import mxhx.ls.utils.SymbolKindUtils;
import languageServerProtocol.Types.InsertTextFormat;
import languageServerProtocol.Types.CompletionItemTag;
import mxhx.symbols.IMXHXSymbol;
import mxhx.symbols.IMXHXTypeSymbol;
import mxhx.ls.utils.MXHXNamespaceUtils;
import haxe.extern.EitherType;
import jsonrpc.CancellationToken;
import jsonrpc.Protocol;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;
import languageServerProtocol.Types.CompletionItem;
import languageServerProtocol.Types.CompletionList;
import languageServerProtocol.protocol.Protocol.CompletionParams;
import languageServerProtocol.protocol.Protocol.CompletionRequest;
import mxhx.internal.MXHXData;
import mxhx.ls.utils.MXHXDataUtils;
import mxhx.symbols.IMXHXClassSymbol;
import mxhx.symbols.IMXHXFieldSymbol;
import mxhx.resolver.IMXHXResolver;
import mxhx.resolver.MXHXResolverTools;

using mxhx.ls.extensions.PositionExtensions;

class CompletionProvider {
	private var resolver:IMXHXResolver;
	private var mxhxDataLookup:Map<String, IMXHXData>;
	private var sourceLookup:Map<String, String>;
	private var completionSupportsSnippets:Bool;
	private var completionSupportsSimpleSnippets:Bool;
	private var completionTypes:Map<String, Bool> = [];

	public function new(protocol:Protocol, resolver:IMXHXResolver, sourceLookup:Map<String, String>, mxhxDataLookup:Map<String, IMXHXData>,
			completionSupportsSnippets:Bool, completionSupportsSimpleSnippets:Bool) {
		this.resolver = cast resolver;
		this.sourceLookup = sourceLookup;
		this.mxhxDataLookup = mxhxDataLookup;
		this.completionSupportsSnippets = completionSupportsSnippets;
		this.completionSupportsSimpleSnippets = completionSupportsSimpleSnippets;

		protocol.onRequest(CompletionRequest.type, onCompletion);
	}

	private function onCompletion(params:CompletionParams, token:CancellationToken, resolve:Null<EitherType<Array<CompletionItem>, CompletionList>>->Void,
			reject:ResponseError<NoData>->Void):Void {
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
		var unitData = mxhxData.findUnitContainingOffset(offset);
		var tagData:IMXHXTagData = null;
		while (unitData != null) {
			if ((unitData is IMXHXTagData)) {
				tagData = cast unitData;
				break;
			}
			unitData = unitData.parentUnit;
		}
		if (tagData == null) {
			resolve(null);
			return;
		}

		final isAttribute = tagData.isOffsetInAttributeList(offset) && offset < tagData.end;
		if (isAttribute && tagData.isCloseTag()) {
			resolve(null);
			return;
		}
		final isTagName = MXHXData.contains(tagData.contentStart, tagData.contentStart + tagData.name.length, offset);

		completionTypes.clear();
		final items:Array<CompletionItem> = [];

		// XmlnsRange xmlnsRange = XmlnsRange.fromOffsetTag(offsetTag, currentOffset);
		// Position xmlnsPosition = null;
		// if (xmlnsRange.endIndex >= 0) {
		//     xmlnsPosition = LanguageServerCompilerUtils.getPositionFromOffset(new StringReader(fileText),
		//             xmlnsRange.endIndex);
		// }

		final includeOpenTagBracket = getTagNeedsOpenBracket(sourceCode, offset);
		final nextChar:String = (sourceCode.length > offset) ? sourceCode.charAt(offset) : null;

		// an implicit offset tag may mean that we're trying to close a tag
		final parentTag = tagData.parentTag;
		if (parentTag != null && tagData.isImplicit()) {
			var nextTag = tagData.getNextTag();
			if (nextTag != null
				&& nextTag.isImplicit()
				&& nextTag.isCloseTag()
				&& nextTag.name == parentTag.name
				&& StringTools.startsWith(parentTag.shortName, tagData.shortName)) {
				var closeTagText = "</" + nextTag.name + ">";
				// strip </ from the insert text
				var insertText = closeTagText.substring(2);
				var prefixLength = tagData.prefix != null ? tagData.prefix.length : 0;
				if (prefixLength > 0) {
					// if the prefix already exists, strip it away so that the
					// editor won't duplicate it.
					insertText = insertText.substring(prefixLength + 1);
				}
				items.push({
					// display the full close tag
					label: closeTagText,
					insertText: insertText,
					sortText: tagData.shortName
				});
			}
		}

		// inside <fx:Declarations>
		if (MXHXDataUtils.isDeclarationsTag(tagData)) {
			if (!isAttribute) {
				autoCompleteDefinitionsForMXHX(tagData, true, includeOpenTagBracket, nextChar, null, items);
			}
			resolve(items);
			return;
		}

		final offsetSymbol = resolver.resolveTag(tagData);
		if (offsetSymbol == null || isTagName) {
			final parentSymbol = parentTag != null ? resolver.resolveTag(parentTag) : null;
			if (parentSymbol != null) {
				if (parentSymbol is IMXHXClassSymbol) {
					var classSymbol:IMXHXClassSymbol = cast parentSymbol;
					var offsetPrefix = tagData.prefix;
					if (offsetPrefix.length == 0 || parentTag.prefix == offsetPrefix) {
						// only add members if the prefix is the same as the
						// parent tag. members can't have different prefixes.
						// also allow members when we don't have a prefix.
						addMembersForMXHXTypeToAutoComplete(classSymbol, parentTag, false, false, offsetPrefix.length == 0, nextChar, items);
					}
				} else {
					// the parent is something like a property, so matching the
					// prefix is not required
					mxhxTypesCompletionFromExistingTag(tagData, nextChar, items);
				}
				resolve(items);
				return;
			} else if (MXHXDataUtils.isDeclarationsTag(parentTag)) {
				mxhxTypesCompletionFromExistingTag(tagData, nextChar, items);
				resolve(items);
				return;
			} else if (mxhxData.rootTag == tagData) {
				mxhxTypesCompletionFromExistingTag(tagData, nextChar, items);
				resolve(items);
				return;
			}
			resolve(items);
			return;
		}

		if (offsetSymbol is IMXHXClassSymbol) {
			var attribute = MXHXDataUtils.getMXHXTagAttributeWithValueAtOffset(tagData, offset);
			if (attribute != null) {
				mxhxAttributeCompletion(tagData, offset, items);
				resolve(items);
				return;
			}
			attribute = MXHXDataUtils.getMXHXTagAttributeWithNameAtOffset(tagData, offset, true);
			if (attribute != null && offset > (attribute.start + attribute.name.length)) {
				// states not supported by MXHX yet
				// mxhxStatesCompletion(offsetUnit, items);
				resolve(items);
				return;
			}

			var classSymbol:IMXHXClassSymbol = cast offsetSymbol;
			addMembersForMXHXTypeToAutoComplete(classSymbol, tagData, isAttribute, includeOpenTagBracket, !isAttribute, nextChar, items);

			if (!isAttribute) {
				var mxmlParent = tagData.parent;
				var mxNS = MXHXNamespaceUtils.getMXHXLanguageNamespace(tagData);
				if (mxmlParent != null && tagData == mxmlParent.rootTag) {
					addRootMXHXLanguageTagsToAutoComplete(tagData, mxNS.prefix, true, includeOpenTagBracket, items);
				}
				addMXHXLanguageTagToAutoComplete("Component", mxNS.prefix, includeOpenTagBracket, true, items);

				var defaultPropertyName = classSymbol.defaultProperty; // if [DefaultProperty] is set, then we can instantiate
				// types as child elements
				// but we don't want to do that when in an attribute
				var allowTypesAsChildren = defaultPropertyName != null && defaultPropertyName.length > 0;
				if (!allowTypesAsChildren) {
					// similar to [DefaultProperty], if a component implements
					// mx.core.IContainer, we can instantiate types as children
					// var containerInterface = project.getContainerInterface();
					// allowTypesAsChildren = classDefinition.isInstanceOf(containerInterface, project);
				}
				if (allowTypesAsChildren) {
					var filterType:IMXHXTypeSymbol = null;
					if (defaultPropertyName != null) {
						// TypeScope
						// typeScope = (TypeScope)
						// classDefinition.getContainedScope();
						// Set<INamespaceDefinition>
						// namespaceSet = ScopeUtils.getNamespaceSetForScopes(typeScope, typeScope, project);
						// var propertiesByName = typeScope.getPropertiesByNameForMemberAccess((CompilerProject) project, defaultPropertyName, namespaceSet);
						// if (propertiesByName.size() > 0) {
						// 	IDefinition
						// 	propertyDefinition = propertiesByName.get(0);
						// 	typeFilter = DefinitionUtils.getMXMLChildElementTypeForDefinition(propertyDefinition, project);
						// }
					}

					autoCompleteDefinitionsForMXHX(tagData, true, includeOpenTagBracket, nextChar, filterType, items);
				}
			}

			resolve(items);
			return;
		}

		if (offsetSymbol is IMXHXFieldSymbol) {
			var fieldSymbol:IMXHXFieldSymbol = cast offsetSymbol;
			if (!isAttribute) {
				autoCompleteDefinitionsForMXHX(tagData, false, includeOpenTagBracket, nextChar, fieldSymbol.type, items);
			}
			resolve(items);
			return;
		}

		trace("Unknown definition for MXHX completion: " + Type.getClassName(Type.getClass(offsetSymbol)));
		resolve(null);
	}

	private function getTagNeedsOpenBracket(sourceCode:String, offset:Int):Bool {
		var tagNeedsOpenBracket = offset == 0;
		if (offset > 0 && offset < sourceCode.length) {
			var prevChar = sourceCode.charAt(offset - 1);
			tagNeedsOpenBracket = prevChar != "<";
		}
		return tagNeedsOpenBracket;
	}

	private function autoCompleteDefinitionsForMXHX(tagData:IMXHXTagData, typesOnly:Bool, includeOpenTagBracket:Bool, nextChar:String,
			filterType:IMXHXTypeSymbol, items:Array<CompletionItem>):Void {
		// var symbols = ([] : Array<IMXHXSymbol>);
		var symbols:Array<IMXHXSymbol> = null; // = resolver.getAllSymbols();
		for (symbol in symbols) {
			var isType = (symbol is IMXHXTypeSymbol);
			if (!typesOnly || isType) {
				if (isType) {
					var typeSymbol:IMXHXTypeSymbol = cast symbol;
					if (typeSymbol.isPrivate) {
						continue;
					}
					if (typeSymbol.pack.indexOf("_internal") != -1) {
						continue;
					}
					// if (filterType != null && !DefinitionUtils.extendsOrImplements(project, typeDefinition, typeFilter)) {
					// 	continue;
					// }
					var discoveredNS = MXHXNamespaceUtils.getMXHXNamespaceForSymbol(typeSymbol, tagData.parent, resolver);
					createMXHXSymbolCompletionItem(symbol, false, discoveredNS.prefix, discoveredNS.uri, includeOpenTagBracket, true, nextChar, tagData, items);
				} else {
					createMXHXSymbolCompletionItem(symbol, false, null, null, includeOpenTagBracket, false, nextChar, tagData, items);
				}
			}
		}
	}

	private function mxhxTypesCompletionFromExistingTag(tagData:IMXHXTagData, nextChar:String, items:Array<CompletionItem>):Void {
		var mxhxData = tagData.parent;
		var tagStartShortNameForComparison = tagData.shortName.toLowerCase();
		var tagPrefix = tagData.prefix;
		var tagNamespace:String = null;
		var prefixMap = mxhxData.getPrefixMapForTag(mxhxData.rootTag);
		if (prefixMap != null) {
			// could be null if this is the root tag and no prefixes are defined
			tagNamespace = prefixMap.getUriForPrefix(tagPrefix);
		}
		var tagNamespacePackage:String = null;
		if (tagNamespace != null && StringTools.endsWith(tagNamespace, "*")) {
			if (tagNamespace.length > 1) {
				tagNamespacePackage = tagNamespace.substring(0, tagNamespace.length - 2);
			} else // top level
			{
				tagNamespacePackage = "";
			}
		}

		// for (module in parsedSources) {
		// 	if (module.decls.length == 0) {
		// 		continue;
		// 	}
		// 	var moduleName = MXHXResolverTools.filePathAndPackToModule(module.decls[0].pos.file, module.pack);
		// 	for (decl in module.decls) {
		// 		var definition:Definition<Dynamic, Dynamic> = switch (decl.decl) {
		// 			case EClass(d): d;
		// 			case EAbstract(d): d;
		// 			case EEnum(d): d;
		// 			case ETypedef(d): d;
		// 			default: null;
		// 		}
		// 		if (definition == null) {
		// 			continue;
		// 		}
		// 		var qname = MXHXResolverTools.definitionToQname(definition.name, module.pack, moduleName);
		// 		var symbol = resolver.resolveQname(qname);
		// 		if (symbol == null) {
		// 			continue;
		// 		}

		// 		// first check that the tag either doesn't have a short name yet
		// 		// or that the definition's base name matches the short name
		// 		if (tagStartShortNameForComparison.length == 0
		// 			|| StringTools.startsWith(symbol.name.toLowerCase(), tagStartShortNameForComparison)) {
		// 			var symbolPackageName = symbol.pack.join(".");
		// 			// if a prefix already exists, make sure the definition is
		// 			// in a namespace with that prefix
		// 			if (tagPrefix != null && tagPrefix.length > 0) {
		// 				var tagNames = resolver.getTagNamesForQname(symbol.qname);
		// 				for (uri => tagName in tagNames) {
		// 					// getTagNamesForClass() returns the all language namespaces, even if that's
		// 					// not what we're using in this file
		// 					if (MXHXDataUtils.isLanguageUri(uri)) {
		// 						// use the language namespace of the root tag instead
		// 						var languageNamespace = MXHXNamespaceUtils.getMXHXLanguageNamespace(mxhxData.rootTag);
		// 						if (languageNamespace != null) {
		// 							uri = languageNamespace.uri;
		// 						}
		// 					}
		// 					if (prefixMap != null) {
		// 						var prefixes = prefixMap.getPrefixesForUri(uri);
		// 						for (otherPrefix in prefixes) {
		// 							if (tagPrefix == otherPrefix) {
		// 								createMXHXSymbolCompletionItem(symbol, false, null, null, false, false, nextChar, tagData, items);
		// 							}
		// 						}
		// 					}
		// 				}
		// 				if (tagNamespacePackage != null && tagNamespacePackage == symbolPackageName) {
		// 					createMXHXSymbolCompletionItem(symbol, false, null, null, false, false, nextChar, tagData, items);
		// 				}
		// 			} else {
		// 				// no prefix yet, so complete the definition with a prefix
		// 				var ns = MXHXNamespaceUtils.getMXHXNamespaceForSymbol(symbol, mxhxData, resolver);
		// 				createMXHXSymbolCompletionItem(symbol, false, ns.prefix, ns.uri, false, true, nextChar, tagData, items);
		// 			}
		// 		}
		// 	}
		// }
	}

	private function mxhxAttributeCompletion(tagData:IMXHXTagData, offset:Int, items:Array<CompletionItem>):Void {
		var attributeSymbol = MXHXDataUtils.getSymbolForMXHXTagAttribute(tagData, offset, true, resolver);
		if (attributeSymbol is IMXHXFieldSymbol) {
			var fieldSymbol:IMXHXFieldSymbol = cast attributeSymbol;
			if (fieldSymbol.type != null && fieldSymbol.type.qname == "Bool") {
				items.push({
					kind: Value,
					label: "false"
				});
				items.push({
					kind: Value,
					label: "true"
				});
				return;
			}
		}
	}

	private function addRootMXHXLanguageTagsToAutoComplete(offsetTag:IMXHXTagData, prefix:String, includeOpenTagPrefix:Bool, includeOpenTagBracket:Bool,
			items:Array<CompletionItem>):Void {
		var item:CompletionItem = {
			label: (prefix != null && prefix.length > 0) ? '${prefix}:Script' : "Script",
			kind: CompletionItemKind.Keyword,
			filterText: "Script",
			sortText: "Script"
		};
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			item.insertTextFormat = Snippet;
		}
		var insertText = "";
		if (includeOpenTagBracket) {
			insertText += "<";
		}
		if (includeOpenTagPrefix && prefix != null && prefix.length > 0) {
			insertText += prefix;
			insertText += ":";
		}
		insertText += "Script>\n\t<![CDATA[\n\t\t";
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			insertText += "$0";
		}
		insertText += "\n\t]]>\n</";
		if (prefix != null && prefix.length > 0) {
			insertText += prefix;
			insertText += ":";
		}
		insertText += "Script>";
		item.insertText = insertText;
		items.push(item);
		addMXHXLanguageTagToAutoComplete("Binding", prefix, includeOpenTagBracket, includeOpenTagPrefix, items);
		addMXHXLanguageTagToAutoComplete("Declarations", prefix, includeOpenTagBracket, includeOpenTagPrefix, items);
		// addMXHXLanguageTagToAutoComplete("Metadata", prefix, includeOpenTagBracket, includeOpenTagPrefix, result);
		// addMXHXLanguageTagToAutoComplete("Style", prefix, includeOpenTagBracket, includeOpenTagPrefix, result);
	}

	private function addMXHXLanguageTagToAutoComplete(tagName:String, prefix:String, includeOpenTagBracket:Bool, includeOpenTagPrefix:Bool,
			items:Array<CompletionItem>):Void {
		var item:CompletionItem = {
			label: (prefix != null && prefix.length > 0) ? '${prefix}:${tagName}' : tagName,
			kind: CompletionItemKind.Keyword,
			filterText: tagName,
			sortText: tagName
		}
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			item.insertTextFormat = Snippet;
		}
		var insertText = "";
		if (includeOpenTagBracket) {
			insertText += "<";
		}
		if (includeOpenTagPrefix && prefix != null && prefix.length > 0) {
			insertText += prefix;
			insertText += ":";
		}
		var escapedTagName = tagName;
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			escapedTagName = ~/\$/g.replace(tagName, "\\$");
		}
		insertText += escapedTagName;
		insertText += ">\n\t";
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			insertText += "$0";
		}
		insertText += "\n</";
		if (prefix != null && prefix.length > 0) {
			insertText += prefix;
			insertText += ":";
		}
		insertText += escapedTagName;
		insertText += ">";
		item.insertText = insertText;
		items.push(item);
	}

	private function addMembersForMXHXTypeToAutoComplete(classSymbol:IMXHXClassSymbol, parentTag:IMXHXTagData, isAttribute:Bool, includeOpenTagBracket:Bool,
			includeOpenTagPrefix:Bool, nextChar:String, items:Array<CompletionItem>):Void {
		var currentClassSymbol = classSymbol;
		while (currentClassSymbol != null) {
			for (field in currentClassSymbol.fields) {
				if (field.isMethod || !field.isPublic || field.isStatic || !field.isWritable) {
					continue;
				}
				createMXHXSymbolCompletionItem(field, isAttribute, parentTag.prefix, parentTag.uri, includeOpenTagBracket, includeOpenTagPrefix, nextChar,
					parentTag, items);
			}
			for (event in currentClassSymbol.events) {
				createMXHXSymbolCompletionItem(event, isAttribute, parentTag.prefix, parentTag.uri, includeOpenTagBracket, includeOpenTagPrefix, nextChar,
					parentTag, items);
			}
			currentClassSymbol = currentClassSymbol.superClass;
		}
		if (isAttribute) {
			addLanguageAttributesToAutoCompleteMXML(classSymbol, nextChar, items);
		}
	}

	private function getFieldByName(classSymbol:IMXHXClassSymbol, fieldName:String):IMXHXFieldSymbol {
		var currentClassSymbol = classSymbol;
		while (currentClassSymbol != null) {
			var idField = Lambda.find(currentClassSymbol.fields, field -> field.name == fieldName);
			if (idField != null) {
				return idField;
			}
			currentClassSymbol = currentClassSymbol.superClass;
		}
		return null;
	}

	private function addLanguageAttributesToAutoCompleteMXML(classSymbol:IMXHXClassSymbol, nextChar:String, items:Array<CompletionItem>):Void {
		// var includeInItem:CompletionItem = {
		// 	label: "includeIn",
		// 	kind: CompletionItemKind.Keyword
		// };
		// if ((completionSupportsSnippets || completionSupportsSimpleSnippets) && nextChar != '=') {
		// 	includeInItem.insertTextFormat = InsertTextFormat.Snippet;
		// 	includeInItem.insertText = "includeIn=\"$0\"";
		// }
		// items.push(includeInItem);

		// var excludeFromItem:CompletionItem = {
		// 	label: "excludeFrom",
		// 	kind: CompletionItemKind.Keyword
		// };
		// if ((completionSupportsSnippets || completionSupportsSimpleSnippets) && nextChar != '=') {
		// 	excludeFromItem.insertTextFormat = InsertTextFormat.Snippet;
		// 	excludeFromItem.insertText = "excludeFrom=\"$0\"";
		// }
		// items.push(excludeFromItem);

		var idField = getFieldByName(classSymbol, "id");
		if (idField == null) {
			// classes may or may not have an id field, but if they don't,
			// MXHX allows the id to be set regardless
			var idItem:CompletionItem = {
				label: "id",
				kind: CompletionItemKind.Keyword
			};
			if ((completionSupportsSnippets || completionSupportsSimpleSnippets) && nextChar != '=') {
				idItem.insertTextFormat = InsertTextFormat.Snippet;
				idItem.insertText = "id=\"$0\"";
			}
			items.push(idItem);
		}
	}

	private function createMXHXSymbolCompletionItem(symbol:IMXHXSymbol, isAttribute:Bool, prefix:String, uri:String, includeOpenTagBracket:Bool,
			includeOpenTagPrefix:Bool, nextChar:String, offsetTagData:IMXHXTagData, items:Array<CompletionItem>):Void {
		if (symbol.meta != null) {
			var noCompletion = Lambda.find(symbol.meta, meta -> meta.name == ":noCompletion");
			if (noCompletion != null) {
				return;
			}
		}
		var typeSymbol:IMXHXTypeSymbol = null;
		if ((symbol is IMXHXTypeSymbol)) {
			typeSymbol = cast symbol;
			var qname = typeSymbol.qname;
			if (completionTypes.exists(qname)) {
				return;
			}
			completionTypes.set(qname, true);
		}
		var symbolBaseName = symbol.name;
		if (symbolBaseName.length == 0) {
			// vscode expects all items to have a name
			return;
		}
		var item = createSymbolCompletionItem(symbol);
		var escapedSymbolBaseName = symbolBaseName;
		if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
			escapedSymbolBaseName = ~/\$/g.replace(symbolBaseName, "\\$");
		}
		if (isAttribute && (completionSupportsSnippets || completionSupportsSimpleSnippets) && nextChar != '=') {
			item.insertTextFormat = InsertTextFormat.Snippet;
			item.insertText = '${escapedSymbolBaseName}="$0"';
		} else if (!isAttribute) {
			if (typeSymbol != null && includeOpenTagPrefix && prefix != null && prefix.length > 0) {
				item.label = ('${prefix}:${symbolBaseName}');
				item.sortText = symbolBaseName;
				item.filterText = symbolBaseName;
			}

			var insertText = "";
			if (includeOpenTagBracket) {
				insertText += "<";
			}
			if (includeOpenTagPrefix && prefix != null && prefix.length > 0) {
				insertText += '${prefix}:';
			}
			insertText += escapedSymbolBaseName;
			/*if (typeSymbol != null
				&& prefix != null
				&& prefix.length > 0
				&& (offsetTagData == null || offsetTagData == offsetTagData.parent.rootTag)
				&& xmlnsPosition == null) {
				// if this is the root tag, we should add the XML namespace and
				// close the tag automatically
				insertTextBuilder.append(" ");
				if (!uri.equals(IMXMLLanguageConstants.NAMESPACE_MXML_2009) && !uri.equals(IMXMLLanguageConstants.NAMESPACE_MXML_2006)) {
					insertTextBuilder.append("xmlns");
					insertTextBuilder.append(":");
					insertTextBuilder.append("fx=\"");
					insertTextBuilder.append(IMXMLLanguageConstants.NAMESPACE_MXML_2009);
					insertTextBuilder.append("\"\n\t");
				}
				insertTextBuilder.append("xmlns");
				insertTextBuilder.append(":");
				insertTextBuilder.append(prefix);
				insertTextBuilder.append("=\"");
				insertTextBuilder.append(uri);
				insertTextBuilder.append("\">\n\t");
				if (completionSupportsSnippets || completionSupportsSimpleSnippets) {
					item.insertTextFormat = Snippet;
					insertTextBuilder.append("$0");
				}
				insertTextBuilder.append("\n</");
				insertTextBuilder.append(prefix);
				insertTextBuilder.append(":");
				insertTextBuilder.append(escapedSymbolBaseName);
				insertTextBuilder.append(">");
			}*/
			if ((completionSupportsSnippets || completionSupportsSimpleSnippets) && typeSymbol == null) {
				item.insertTextFormat = Snippet;
				insertText += ">$0</";
				if (prefix != null && prefix.length > 0) {
					insertText += '${prefix}:';
				}
				insertText += '${escapedSymbolBaseName}>';
			} else if ((symbol is IMXHXFieldSymbol)) {
				// fields can't have attributes, so we can close the tag
				insertText += ">";
			}
			item.insertText = insertText;
			// if (typeSymbol != null
			// 	&& prefix != null
			// 	&& prefix.length > 0
			// 	&& uri != null
			// 	&& MXMLDataUtils.needsNamespace(offsetTag, prefix, uri)
			// 	&& xmlnsPosition != null) {
			// 	var textEdit = CodeActionsUtils.createTextEditForAddMXMLNamespace(prefix, uri, xmlnsPosition);
			// 	if (textEdit != null) {
			// 		item.setAdditionalTextEdits(Collections.singletonList(textEdit));
			// 	}
			// }
		}
		items.push(item);
	}

	private static function createSymbolCompletionItem(symbol:IMXHXSymbol):CompletionItem {
		var item:CompletionItem = {
			label: symbol.name,
			kind: SymbolKindUtils.symbolToCompletionItemKind(symbol),
			detail: SymbolTextUtils.symbolToDetail(symbol),
			documentation: symbol.doc
		};

		var tags:Array<CompletionItemTag> = [];
		// if (symbol.deprecated) {
		// 	tags.push(CompletionItemTag.Deprecated);
		// }
		if (tags.length > 0) {
			item.tags = tags;
		}
		return item;
	}
}
