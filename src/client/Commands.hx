package client;

enum abstract CommandId(String) {
	var Help = "/help";
	var Clear = "/clear";
	var Ban = "/ban";
	var Unban = "/unban";
	var Kick = "/kick";
	var Ad = "/ad";
	var Volume = "/volume";
	var Dump = "/dump";
	var Crash = "/crash";
	var Flashback = "/fb";

	public inline function toString():String {
		return this;
	}
}

@:structInit
class CommandInfo {
	public final name:CommandId;
	public final aliases:Array<String>;
	public final args:Int;
	public final lang:String;

	public function new(name:CommandId, args = 0, ?aliases:Array<String>) {
		this.name = name;
		this.args = args;
		this.aliases = aliases ?? [];
		lang = getLangId();
	}

	function getLangId():String {
		final withoutSlash = name.toString().substr(1);
		return "cmd" + withoutSlash.charAt(0).toUpperCase() + withoutSlash.substr(1);
	}
}

typedef ParsedCommand = {
	final cmd:Null<CommandInfo>;
	final rawCmd:String;
	final args:Array<String>;
	final currentArgIndex:Int;
}

class Commands {
	static final list:Array<CommandInfo> = [
		{
			name: Help,
		},
		{
			name: Clear,
		},
		{
			name: Ban,
			args: 2,
		},
		{
			name: Unban,
			args: 1,
		},
		{
			name: Kick,
			args: 1,
		},
		{
			name: Ad,
		},
		{
			name: Volume,
			args: 1,
		},
		{
			name: Dump,
		},
		{
			name: Crash,
		},
		{
			name: Flashback,
			aliases: ["/flashback"],
		}
	];

	public static function find(name:String):Null<CommandInfo> {
		final lower = name.toLowerCase();
		for (c in list) {
			if (c.name.toString() == lower) return c;
			for (a in c.aliases) {
				if (a.toLowerCase() == lower) return c;
			}
		}
		return null;
	}

	public static function parse(input:String):ParsedCommand {
		if (!input.startsWith("/")) {
			return {
				cmd: null,
				rawCmd: "",
				args: [],
				currentArgIndex: -1
			};
		}
		final parts = input.split(" ");
		final rawCmd = parts[0];
		final args = parts.slice(1);
		final currentArgIndex = args.length > 0 ? args.length - 1 : -1;

		return {
			cmd: find(rawCmd),
			rawCmd: rawCmd,
			args: args,
			currentArgIndex: currentArgIndex
		};
	}

	public static function filterForAutocomplete(val:String):Array<CommandInfo> {
		if (!val.startsWith("/")) return [];
		final parts = val.toLowerCase().split(" ");
		final searchCmd = parts[0];
		final spaceCount = parts.length - 1;

		final result:Array<CommandInfo> = [];
		for (c in list) {
			if (spaceCount == 0) {
				if (c.name.toString().startsWith(searchCmd)) {
					result.push(c);
				} else {
					for (a in c.aliases) {
						if (a.toLowerCase().startsWith(searchCmd)) {
							result.push(c);
							break;
						}
					}
				}
			} else {
				if (spaceCount <= c.args) {
					if (c.name.toString() == searchCmd) {
						result.push(c);
					} else {
						for (a in c.aliases) {
							if (a.toLowerCase() == searchCmd) {
								result.push(c);
								break;
							}
						}
					}
				}
			}
		}
		return result;
	}

	public static function formatDescWithHighlight(desc:String, activeArgIndex:Int):String {
		desc = StringTools.htmlEscape(desc);

		var argCounter = 0;
		final argRegex = ~/&lt;[^&]+&gt;/g;
		desc = argRegex.map(desc, reg -> {
			final token = reg.matched(0);
			final isCurrent = (argCounter == activeArgIndex);
			argCounter++;
			if (isCurrent) {
				return '<span class="chat-command-arg-active">' + token + '</span>';
			} else {
				return token;
			}
		});

		final codeRegex = ~/`([^`]+)`/g;
		return codeRegex.map(desc, reg -> {
			return '<span class="chat-command-code">' + reg.matched(1) + '</span>';
		});
	}
}
