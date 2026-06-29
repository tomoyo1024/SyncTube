package server.cache;

import haxe.io.Path;
import js.lib.Promise;
import js.node.ChildProcess;
import js.node.child_process.ChildProcess as ChildProcessObject;
import sys.FileSystem;
import ytdlp_nodejs.ArgsOptions;
import ytdlp_nodejs.VideoInfo;
import ytdlp_nodejs.VideoProgress;
import ytdlp_nodejs.YtDlp;

typedef YtdlpHandlers = {
	final onProgress:(p:VideoProgress) -> Void;
	final onComplete:() -> Void;
	final onError:(err:String) -> Void;
}

class YtdlpCache {
	final main:Main;
	final cache:Cache;
	var ytDlp:Null<YtDlp>;

	public function new(main:Main, cache:Cache):Void {
		this.main = main;
		this.cache = cache;
	}

	public function checkYtDeps():Bool {
		try {
			ChildProcess.execSync("ffmpeg -version", {stdio: "ignore", timeout: 5000});
			ytDlp = js.Syntax.code("new (require('ytdlp-nodejs')).YtDlp()");
			return true;
		} catch (e) {
			return false;
		}
	}

	public function checkUpdate():Void {
		ytDlp.execAsync("", {
			updateTo: main.config.ytDlp.channel,
			onData: d -> {
				trace(d);
			}
		}).catchError(e -> {
			trace(e);
		});
	}

	public function cleanInputFiles(prefix = "__tmp"):Void {
		final names = FileSystem.readDirectory(cache.cacheDir);
		for (name in names) {
			if (!name.startsWith(prefix)) continue;
			cache.remove(name);
		}
	}

	public function getInfoAsync(url:String, useCookies = false):Promise<VideoInfo> {
		return cast ytDlp.getInfoAsync(url, cast {
			cookies: useCookies ? getCookiesPathOrNull() : null,
			additionalOptions: ytExtraOptions(),
		});
	}

	public function getCookiesPathOrNull():Null<String> {
		final cookiesPath = '${main.userDir}/cookies.txt';
		return FileSystem.exists(cookiesPath) ? cookiesPath : null;
	}

	public function ytExtraOptions():Array<String> {
		return ["--no-js-runtimes", "--js-runtimes", main.config.ytDlp.jsRuntime];
	}

	/**
		Runs `yt-dlp <url> --ies default,-generic` to check if a site-specific
		extractor handles the url. Returns the process so it can be killed on cancel.
	**/
	public function checkUrlSupported(url:String, callback:(supported:Bool) -> Void):ChildProcessObject {
		final process:ChildProcessObject = ytDlp.exec(url, {
			useExtractors: ["default", "-generic"],
			simulate: true,
			quiet: true,
			socketTimeout: 5,
			extractorRetries: 0,
		});
		var done = false;
		inline function finish(supported:Bool):Void {
			if (done) return;
			done = true;
			callback(supported);
		}
		process.on("close", (code:Int, _signal:String) -> finish(code == 0));
		process.on("error", (_err:Dynamic) -> finish(false));
		return process;
	}

	/**
		Spawns yt-dlp as a manual process and wires progress/completion to `handlers`.
		Returns the process so the caller can kill it on cancel.
	**/
	public function download(url:String, options:ArgsOptions, handlers:YtdlpHandlers):ChildProcessObject {
		final process:ChildProcessObject = ytDlp.exec(url, options);
		var stderr = "";
		var done = false;
		process.stderr.on("data", (d:Dynamic) -> stderr += d);
		process.on("progress", (p:VideoProgress) -> handlers.onProgress(p));
		process.on("close", (code:Int, _signal:String) -> {
			if (done) return;
			done = true;
			if (code == 0) handlers.onComplete();
			else handlers.onError('yt-dlp exited with code $code: $stderr');
		});
		process.on("error", (err:Dynamic) -> {
			if (done) return;
			done = true;
			handlers.onError('Failed to start yt-dlp process: $err');
		});
		return process;
	}

	/**
		Generic best-quality download to mp4 for vk and other site-specific
		extractors. Used after `checkUrlSupported` succeeds (or directly for vk).
	**/
	public function cacheVideo(client:Client, url:String, cb:CacheCallbacks):Void {
		final clientName = client.name;
		final outName = deriveOutName(url);
		trace('Caching $url to $outName...');
		cb.onResolved(cache.getFileUrl(outName));

		final inName = '__tmp-${Std.random(0xFFFFFF)}-${Path.withoutExtension(outName)}';
		var canceled = false;
		var process:Null<ChildProcessObject> = null;
		inline function cleanup():Void {
			cleanInputFiles(inName);
		}
		if (cb.registerCancel != null) cb.registerCancel(() -> {
			canceled = true;
			process?.kill();
			cleanup();
		});

		var useCookies = false;
		var lastSentRatio = 0.0;

		function onGetInfo(info:VideoInfo):Void {
			if (canceled) return;
			if (cb.onMetadata != null) cb.onMetadata(info.title, info.duration);
			if (!cache.removeOlderCache(estimateSize(info) * 2 + cache.freeSpaceBlock)) {
				cleanup();
				cb.onError();
				log(clientName, cache.notEnoughSpaceErrorText);
				return;
			}
			process = download(url, {
				output: '${cache.cacheDir}/$inName',
				remuxVideo: "mp4",
				additionalOptions: ytExtraOptions(),
				cookies: useCookies ? getCookiesPathOrNull() : null,
				forceIpv4: true,
				socketTimeout: 5,
				extractorRetries: 0,
			}, {
				onProgress: p -> {
					if (canceled) return;
					final ratio = p.status == "finished" ? 1.0 : (p.downloaded / p.total)
						.clamp(0, 1);
					if (ratio - lastSentRatio < 0.01 && ratio < 1) return;
					lastSentRatio = ratio;
					cb.onProgress(ratio.toFixed(4));
				},
				onComplete: () -> {
					if (canceled) {
						cleanup();
						return;
					}
					final name = cache.findFile(n -> n.startsWith(inName)) ?? {
						final err = 'Error: cannot find downloaded file with prefix $inName';
						cache.logWithAdmins(client, err);
						cb.onError();
						return;
					};
					FileSystem.rename('${cache.cacheDir}/$name', '${cache.cacheDir}/$outName');
					cleanup();
					cache.add(outName);
					cb.onComplete();
				},
				onError: err -> {
					if (canceled) return;
					cache.logWithAdmins(client, "Error during video download: " + err);
					cleanup();
					cb.onError();
				}
			});
		}

		getInfoAsync(url, useCookies).then(onGetInfo).catchError(err -> {
			if (canceled) return;
			useCookies = true;
			getInfoAsync(url, useCookies).then(onGetInfo).catchError(err -> {
				cleanup();
				cb.onError();
				log(clientName, "" + err);
			});
		});
	}

	function deriveOutName(url:String):String {
		final decoded = try url.urlDecode() catch (e) url;
		var last = decoded.substr(decoded.lastIndexOf("/") + 1);
		final q = last.indexOf("?");
		if (q != -1) last = last.substr(0, q);
		last = Path.withoutExtension(last);
		if (last == "") last = "video";
		return cache.getFreeFileName('$last.mp4');
	}

	function estimateSize(info:VideoInfo):Int {
		final d:Dynamic = info;
		final size:Null<Float> = d.filesize_approx ?? d.filesize;
		return Std.int(size ?? 0);
	}

	function log(clientName:String, msg:String):Void {
		cache.logByName(clientName, msg);
	}
}
