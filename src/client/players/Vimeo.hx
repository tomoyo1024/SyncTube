package client.players;

import Types.PlayerType;
import Types.VideoData;
import Types.VideoDataRequest;
import Types.VideoItem;
import client.IPlayer;
import client.JsApi;
import client.Main.getEl;
import client.Main;
import haxe.Constraints.Function;
import haxe.Http;
import haxe.Json;
import js.Browser.document;
import js.Browser.window;
import js.Syntax;
import js.html.Element;
import js.lib.Promise;

private typedef VimeoPlayerOptions = {
	?url:String,
	?id:Int,
	?autoplay:Bool,
	?playsinline:Bool,
	?responsive:Bool,
}

private extern class VimeoPlayer {
	function play():Promise<Void>;
	function pause():Promise<Void>;
	function setCurrentTime(seconds:Float):Promise<Float>;
	function getCurrentTime():Promise<Float>;
	function getDuration():Promise<Float>;
	function setVolume(volume:Float):Promise<Float>;
	function getVolume():Promise<Float>;
	function setMuted(muted:Bool):Promise<Bool>;
	function getMuted():Promise<Bool>;
	function setPlaybackRate(rate:Float):Promise<Float>;
	function getPlaybackRate():Promise<Float>;
	function destroy():Promise<Void>;
	function on(event:String, callback:Function):Void;
	function off(event:String, callback:Function):Void;
}

class Vimeo implements IPlayer {
	static var isApiLoaded = false;
	static var isApiLoading = false;
	static var apiCallbacks:Array<() -> Void> = [];

	final main:Main;
	final player:Player;
	final playerEl:Element = getEl("#ytapiplayer");
	var video:Element;
	var vimeoPlayer:VimeoPlayer;

	var isLoaded = false;
	var isPausedState = true;
	var currentTime:Float = 0;
	var playbackRate:Float = 1;
	var volume:Float = 1;
	var prevTime:Float = 0;

	public function new(main:Main, player:Player) {
		this.main = main;
		this.player = player;
	}

	public function getPlayerType():PlayerType {
		return VimeoType;
	}

	final matchVimeo = ~/(?:vimeo\.com|player\.vimeo\.com)/i;
	final matchVimeoId = ~/vimeo\.com\/(?:channels\/(?:\w+\/)?|groups\/[^\/]+\/videos\/|video\/|ondemand\/[^\/]+\/)?([0-9]+)/i;

	public function isSupportedLink(url:String):Bool {
		return matchVimeo.match(url) && extractVideoId(url).length > 0;
	}

	public function extractVideoId(url:String):String {
		if (!matchVimeoId.match(url)) return "";
		return matchVimeoId.matched(1);
	}

	function loadApi(callback:() -> Void):Void {
		if (isApiLoaded) {
			callback();
			return;
		}
		apiCallbacks.push(callback);
		if (isApiLoading) return;
		isApiLoading = true;

		JsApi.addScriptToHead("https://player.vimeo.com/api/player.js", () -> {
			isApiLoaded = true;
			isApiLoading = false;
			for (cb in apiCallbacks) cb();
			apiCallbacks = [];
		});
	}

	public function getVideoData(data:VideoDataRequest, callback:(data:VideoData) -> Void):Void {
		final url = data.url;
		if (!isSupportedLink(url)) {
			callback({duration: 0});
			return;
		}
		final oembedUrl = 'https://vimeo.com/api/oembed.json?url=${url.urlEncode()}';
		final http = new Http(oembedUrl);
		http.onData = text -> {
			try {
				final json:{?title:String, ?duration:Float} = Json.parse(text);
				final title:String = json.title ?? "Vimeo video";
				final duration:Float = json.duration ?? 0;
				callback({
					duration: duration,
					title: title,
					url: url
				});
			} catch (e) {
				getRemoteDataFallback(url, callback);
			}
		};
		http.onError = msg -> getRemoteDataFallback(url, callback);
		http.request();
	}

	function getRemoteDataFallback(url:String, callback:(data:VideoData) -> Void):Void {
		if (!isApiLoaded) {
			loadApi(() -> getRemoteDataFallback(url, callback));
			return;
		}
		final tempVideo = document.createDivElement();
		tempVideo.className = "temp-videoplayer";
		tempVideo.style.display = "none";
		playerEl.appendChild(tempVideo);

		var tempPlayer:VimeoPlayer = null;
		final options:VimeoPlayerOptions = {url: url};
		tempPlayer = Syntax.code("new window.Vimeo.Player({0}, {1})", tempVideo, options);
		tempPlayer.on("loaded", () -> {
			tempPlayer.getDuration().then(dur -> {
				try {
					tempPlayer.destroy();
				} catch (e) {}
				if (playerEl.contains(tempVideo)) playerEl.removeChild(tempVideo);
				callback({
					title: "Vimeo video",
					duration: dur,
					url: url
				});
			});
		});
		tempPlayer.on("error", err -> {
			try {
				tempPlayer.destroy();
			} catch (e) {}
			if (playerEl.contains(tempVideo)) playerEl.removeChild(tempVideo);
			callback({duration: 0});
		});
	}

	public function loadVideo(item:VideoItem):Void {
		if (!isApiLoaded) {
			loadApi(() -> loadVideo(item));
			return;
		}

		removeVideo();

		video = document.createDivElement();
		video.id = "videoplayer";
		playerEl.appendChild(video);

		final options:VimeoPlayerOptions = {
			url: item.url,
			autoplay: true,
			playsinline: true,
			responsive: true
		};

		vimeoPlayer = Syntax.code("new window.Vimeo.Player({0}, {1})", video, options);

		vimeoPlayer.on("loaded", () -> {
			if (!main.isAutoplayAllowed()) {
				vimeoPlayer.setVolume(0);
			}
			isLoaded = true;
			if (main.lastState.paused) {
				vimeoPlayer.pause();
			}
			player.onCanBePlayed();
		});

		vimeoPlayer.on("play", () -> {
			isPausedState = false;
			if (!isLoaded) {
				isLoaded = true;
				player.onCanBePlayed();
			}
			player.onPlay();
		});

		vimeoPlayer.on("pause", () -> {
			isPausedState = true;
			if (!isLoaded) {
				isLoaded = true;
				player.onCanBePlayed();
			}
			player.onPause();
		});

		vimeoPlayer.on("timeupdate", (data:{
			seconds:Float,
			percent:Float,
			duration:Float
		}) -> {
			final sec:Float = data.seconds;
			currentTime = sec;
			final diff = Math.abs(prevTime - sec);
			prevTime = sec;
			if (diff > 1) player.onSetTime();
		});

		vimeoPlayer.on("ratechange", (data:{playbackRate:Float}) -> {
			playbackRate = data.playbackRate;
			player.onRateChange();
		});

		vimeoPlayer.on("volumechange", (data:{volume:Float}) -> {
			volume = data.volume;
		});

		vimeoPlayer.on("error", data -> {
			trace('Vimeo error: $data');
		});
	}

	public function removeVideo():Void {
		if (video == null) return;
		isLoaded = false;
		isPausedState = true;
		if (vimeoPlayer != null) {
			try {
				vimeoPlayer.destroy();
			} catch (e) {
				trace(e);
			}
			vimeoPlayer = null;
		}
		if (playerEl.contains(video)) playerEl.removeChild(video);
		video = null;
	}

	public function isVideoLoaded():Bool {
		return isLoaded;
	}

	public function play():Void {
		if (vimeoPlayer != null) vimeoPlayer.play();
	}

	public function pause():Void {
		if (vimeoPlayer != null) vimeoPlayer.pause();
	}

	public function isPaused():Bool {
		return isPausedState;
	}

	public function getTime():Float {
		return currentTime;
	}

	public function setTime(time:Float):Void {
		currentTime = time;
		if (vimeoPlayer != null) vimeoPlayer.setCurrentTime(time);
	}

	public function getPlaybackRate():Float {
		return playbackRate;
	}

	public function setPlaybackRate(rate:Float):Void {
		playbackRate = rate;
		if (vimeoPlayer != null) vimeoPlayer.setPlaybackRate(rate);
	}

	public function getVolume():Float {
		return volume;
	}

	public function setVolume(vol:Float):Void {
		volume = vol;
		if (vimeoPlayer != null) vimeoPlayer.setVolume(vol);
	}

	public function unmute():Void {
		if (vimeoPlayer == null) return;
		vimeoPlayer.setMuted(false);
		vimeoPlayer.setVolume(1);
	}
}
