package mxhx.ls.extensions;

import languageServerProtocol.Types.Position;

class PositionExtensions {
	public static function fromOffset(targetOffset:Int, fileText:String):Position {
		var offset = 0;
		var line = 0;
		var character = 0;

		final textLength = fileText.length;
		while (offset < targetOffset && offset < textLength) {
			var next = fileText.charAt(offset);
			offset++;
			character++;

			if (next == '\n') {
				line++;
				character = 0;
			}
		}
		return {line: line, character: character};
	}

	public static function toOffset(position:Position, fileText:String):Int {
		var targetLine = position.line;
		var targetCharacter = position.character;
		try {
			var offset = 0;
			var line = 0;
			var character = 0;
			var current = 0;
			while (line < targetLine) {
				var next = fileText.charAt(current);
				current++;
				if (next.length == 0) {
					return offset;
				} else {
					// don't skip \r here if line endings are \r\n in the file
					// there may be cases where the file line endings don't match
					// what the editor ends up rendering. skipping \r will help
					// that, but it will break other cases.
					offset++;
					if (next == '\n') {
						line++;
					}
				}
			}
			while (character < targetCharacter) {
				var next = fileText.charAt(current);
				current++;
				if (next.length == 0) {
					return offset;
				} else {
					offset++;
					character++;
				}
			}
			return offset;
		} catch (e:Dynamic) {
			return -1;
		}
	}
}
