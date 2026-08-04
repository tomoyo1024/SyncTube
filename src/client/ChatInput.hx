package client;

import client.Main.getEl;
import haxe.Timer;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.html.Event;
import js.html.InputElement;
import js.html.KeyboardEvent;

class ChatInput {
	public final chatline:InputElement;
	public final commandsWrap:Element;
	public final commandsList:Element;
	public final inputWithHistory:InputWithHistory;

	final main:Main;
	var filteredCommands:Array<Commands.CommandInfo> = [];
	var selectedCommandIndex = -1;

	public function new(main:Main) {
		this.main = main;
		chatline = getEl("#chatline");
		commandsWrap = getEl("#chat-commands-wrap");
		commandsList = getEl("#chat-commands-list");

		setupFocusHandler();
		setupAutocomplete();

		inputWithHistory = new InputWithHistory(chatline, 50, onEnter, onInterceptKeyDown);
	}

	function setupFocusHandler():Void {
		chatline.onfocus = e -> {
			if (Utils.isIOS()) {
				final startY = 0;
				Timer.delay(() -> {
					window.scrollBy(0, -(window.scrollY - startY));
					getEl("#video").scrollTop = 0;
					main.scrollChatToEnd();
				}, 100);
			} else if (Utils.isTouch()) {
				main.scrollChatToEnd();
			}
		};
	}

	function setupAutocomplete():Void {
		commandsList.addEventListener("mousemove", e -> {
			commandsList.classList.remove("keyboard-nav");
		});

		chatline.addEventListener("input", e -> {
			final val = chatline.value;
			if (val.startsWith("/")) {
				filteredCommands = Commands.filterForAutocomplete(val);
				selectedCommandIndex = filteredCommands.length > 0 ? 0 : -1;
				renderCommands();
			} else {
				commandsWrap.style.display = "none";
				selectedCommandIndex = -1;
			}
		});

		chatline.addEventListener("blur", e -> {
			commandsWrap.style.display = "none";
		});
	}

	function renderCommands():Void {
		commandsList.innerHTML = "";
		if (filteredCommands.length == 0) {
			commandsWrap.style.display = "none";
			return;
		}

		final parsed = Commands.parse(chatline.value);
		final currentArgIndex = parsed.currentArgIndex;

		for (i in 0...filteredCommands.length) {
			final cmd = filteredCommands[i];
			final item = document.createDivElement();
			item.className = "chat-command-item" + (i == selectedCommandIndex ? " active" : "");
			item.onclick = e -> {
				chatline.value = cmd.name + (cmd.args > 0 ? " " : "");
				chatline.focus();
				if (cmd.args == 0) {
					commandsWrap.style.display = "none";
					selectedCommandIndex = -1;
				} else {
					chatline.dispatchEvent(new Event("input"));
				}
				return;
			};
			item.onmouseenter = e -> {
				if (!commandsList.classList.contains("keyboard-nav")) {
					selectedCommandIndex = i;
					for (j in 0...commandsList.children.length) {
						final child = commandsList.children[j];
						if (j == i) child.classList.add("active");
						else child.classList.remove("active");
					}
				}
			};

			final nameDiv = document.createDivElement();
			nameDiv.className = "chat-command-item-name";
			nameDiv.innerText = cmd.name.toString();

			final descDiv = document.createDivElement();
			descDiv.className = "chat-command-item-desc";
			descDiv.innerHTML = Commands.formatDescWithHighlight(Lang.get(cmd.lang), currentArgIndex);

			item.appendChild(nameDiv);
			item.appendChild(descDiv);
			commandsList.appendChild(item);
		}
		commandsWrap.style.display = "";
		if (selectedCommandIndex >= 0 && commandsList.children.length > selectedCommandIndex) {
			final selectedEl:Element = cast commandsList.children[selectedCommandIndex];
			untyped selectedEl.scrollIntoView({block: "center"});
		}
	}

	function onEnter(value:String):Bool {
		if (main.handleCommands(value)) return true;
		main.send({
			type: Message,
			message: {
				clientName: "",
				text: value
			}
		});
		if (Utils.isTouch()) chatline.blur();
		commandsWrap.style.display = "none";
		return true;
	}

	function onInterceptKeyDown(e:KeyboardEvent):Bool {
		if (commandsWrap.style.display == "none") return false;
		final key:KeyCode = cast e.keyCode;
		switch key {
			case Up:
				commandsList.classList.add("keyboard-nav");
				if (selectedCommandIndex > 0) selectedCommandIndex--;
				else selectedCommandIndex = filteredCommands.length - 1;
				renderCommands();
				e.preventDefault();
				return true;
			case Down:
				commandsList.classList.add("keyboard-nav");
				if (selectedCommandIndex < filteredCommands.length - 1) selectedCommandIndex++;
				else selectedCommandIndex = 0;
				renderCommands();
				e.preventDefault();
				return true;
			case Return, Tab:
				if (selectedCommandIndex < 0 || selectedCommandIndex >= filteredCommands.length) {
					return false;
				}
				final selectedCmd = filteredCommands[selectedCommandIndex];
				final val = chatline.value;
				final hasSpace = val.indexOf(" ") >= 0;

				if (key == Return) {
					if (hasSpace
						|| (selectedCmd.args == 0
							&& val.trim().toLowerCase() == selectedCmd.name.toString())) {
						return false;
					}
				}

				if (!hasSpace) {
					chatline.value = selectedCmd.name + (selectedCmd.args > 0 ? " " : "");
				}

				e.preventDefault();
				chatline.dispatchEvent(new Event("input"));
				return true;
			case Escape:
				commandsWrap.style.display = "none";
				return false;
			case _:
				return false;
		}
	}
}
